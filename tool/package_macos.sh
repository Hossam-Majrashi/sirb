#!/usr/bin/env bash
# Native macOS packaging. Unsigned/ad-hoc builds are CI artifacts only.
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${SIRB_MACOS_ARCH:-universal}"
case "$arch" in x86_64|arm64|universal) ;; *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;; esac
version="$(python3 tool/release.py version)"
work="$(mktemp -d "${TMPDIR:-/tmp}/sirb-package.XXXXXX")"
keychain=""
cleanup() {
  [[ -z "$keychain" ]] || security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
sign="${SIRB_RELEASE_SIGN:-0}"
if [[ "$sign" == 1 ]]; then
  for key in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGN_IDENTITY MACOS_NOTARY_KEY_ID MACOS_NOTARY_ISSUER_ID MACOS_NOTARY_KEY_P8_BASE64; do
    [[ -n "${!key:-}" ]] || { echo "Release requires GitHub secret: $key" >&2; exit 1; }
  done
fi
# Prepare both CEF/Flutter slices, then thin EVERY Mach-O for single-arch DMGs.
# This avoids mixing an ARM-only Flutter engine with a universal CEF helper.
export WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release
flutter config --no-enable-macos-arm64-only
flutter pub get
flutter precache --macos
# CocoaPods can skip prepare_command for path/development pods.
bash third_party/webview_cef/macos/scripts/download_cef.sh
(cd macos; pod install)
flutter build macos --release
app="$PWD/build/macos/Build/Products/Release/Sirb.app"
[[ -d "$app" ]] || { echo 'Missing Sirb.app' >&2; exit 1; }
export SIRB_MACOS_APP="$app" SIRB_MACOS_ARCH="$arch"
python3 - <<'PY'
import os, pathlib, subprocess
app=pathlib.Path(os.environ['SIRB_MACOS_APP'])
arch=os.environ['SIRB_MACOS_ARCH']
expected={'arm64','x86_64'} if arch=='universal' else {arch}
required=[app/'Contents/MacOS/Sirb',app/'Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework']
helpers=list((app/'Contents/Frameworks').glob('* Helper*.app'))
if len(helpers)!=5:raise SystemExit('Missing CEF helper app bundles')
for path in required:
 if not path.is_file():raise SystemExit('Missing native payload: '+str(path))
count=0
for path in app.rglob('*'):
 if path.is_symlink() or not path.is_file():continue
 kind=subprocess.check_output(['file','-b',str(path)],text=True)
 if not kind.startswith('Mach-O'):continue
 have=set(subprocess.check_output(['lipo','-archs',str(path)],text=True).split())
 if not expected<=have:raise SystemExit(f'Missing {expected-have} in {path}')
 if arch!='universal' and have!=expected:
  thin=path.with_name(path.name+'.thin')
  subprocess.run(['lipo',str(path),'-thin',arch,'-output',str(thin)],check=True)
  thin.chmod(path.stat().st_mode);thin.replace(path)
 count+=1
if count<8:raise SystemExit('Incomplete macOS native payload')
print('Validated Mach-O payloads:',count,arch)
PY
if [[ "$sign" == 1 ]]; then
  python3 - "$work" <<'PY'
import base64, os, pathlib, sys
work=pathlib.Path(sys.argv[1])
for name,key in [('certificate.p12','MACOS_CERTIFICATE_P12_BASE64'),('notary.p8','MACOS_NOTARY_KEY_P8_BASE64')]:
 path=work/name;path.write_bytes(base64.b64decode(os.environ[key],validate=True));path.chmod(0o600)
PY
  keychain="$work/signing.keychain-db"
  password="$(python3 -c 'import secrets;print(secrets.token_hex(32))')"
  security create-keychain -p "$password" "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security import "$work/certificate.p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
  export SIRB_SIGN_KEYCHAIN="$keychain"
fi
export SIRB_RELEASE_SIGN="$sign"
python3 - <<'PY'
import os, pathlib, subprocess
app=pathlib.Path(os.environ['SIRB_MACOS_APP'])
release=os.environ['SIRB_RELEASE_SIGN']=='1'
base=['codesign','--force','--sign',os.environ['MACOS_SIGN_IDENTITY'] if release else '-']
base+=['--keychain',os.environ['SIRB_SIGN_KEYCHAIN'],'--options','runtime','--timestamp'] if release else ['--timestamp=none']
helper='third_party/webview_cef/macos/helper/Helper.entitlements'
for path in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
 if path.is_symlink():continue
 if path.is_file() and subprocess.check_output(['file','-b',str(path)],text=True).startswith('Mach-O'):
  ent=['--entitlements',helper] if '/Contents/MacOS/' in str(path) else []
  subprocess.run(base+ent+[str(path)],check=True)
 elif path.is_dir() and path.suffix in ('.framework','.app'):
  ent=['--entitlements',helper] if path.suffix=='.app' else []
  subprocess.run(base+ent+[str(path)],check=True)
subprocess.run(base+['--entitlements','macos/Runner/Release.entitlements',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],check=True)
PY
notarize() {
  xcrun notarytool submit "$1" --key "$work/notary.p8" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" --wait
  xcrun stapler staple "$2"
  xcrun stapler validate "$2"
}
if [[ "$sign" == 1 ]]; then
  ditto -c -k --keepParent "$app" "$work/notary.zip"
  notarize "$work/notary.zip" "$app"
  spctl --assess --type execute --verbose "$app"
fi
mkdir -p "$work/dmg" dist
cp -R "$app" "$work/dmg/"
ln -s /Applications "$work/dmg/Applications"
dmg="$PWD/dist/sirb-$version-macos-$arch.dmg"
hdiutil create -volname Sirb -srcfolder "$work/dmg" -ov -format UDZO "$dmg"
if [[ "$sign" == 1 ]]; then
  codesign --force --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" --timestamp "$dmg"
  notarize "$dmg" "$dmg"
fi
python3 tool/release.py checksums dist --system macos --arch "$arch"
