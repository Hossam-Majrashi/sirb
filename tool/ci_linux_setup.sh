#!/usr/bin/env bash
# Native x86_64/aarch64 GitHub Linux runner prerequisites (not an app installer).
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Run only on a GitHub Actions runner' >&2; exit 1; }
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libxi-dev libgl1-mesa-dev libglu1-mesa-dev llvm ruby-dev rpm zstd zsync \
  squashfs-tools flatpak flatpak-builder dbus-x11 python3
sudo gem install fpm -v 1.17.0 --no-document
# Ubuntu 24.04's runner-wide AppArmor userns restriction can block builder's
# bubblewrap. This changes ONLY the ephemeral CI host, never the shipped app.
if [[ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
fi
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# Bootstrap the official SDK on ARM, too; Flutter publishes no ARM Linux SDK
# archive for this version, but its pinned git checkout downloads native Dart.
# AppImage tools/runtime are pinned to immutable-version URLs AND SHA-256.
tools="$RUNNER_TEMP/appimage-tools"
mkdir -p "$tools"
export SIRB_TOOLS_DIR="$tools"
python3 - <<'PY'
import hashlib, os, pathlib, platform, urllib.request
arch=platform.machine()
pins={
 'x86_64': ('ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0', '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d'),
 'aarch64': ('f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158', '00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444'),
}
checks=pins[arch]
base=pathlib.Path(os.environ['SIRB_TOOLS_DIR'])
for name,url,expected in [
 ('appimagetool.AppImage', f'https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-{arch}.AppImage', checks[0]),
 ('runtime', f'https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-{arch}', checks[1]),
]:
 path=base/name
 urllib.request.urlretrieve(url,path)
 with path.open('rb') as stream: actual=hashlib.file_digest(stream,'sha256').hexdigest()
 if actual!=expected: raise SystemExit('Tool checksum mismatch: '+name)
 path.chmod(0o755)
PY
(cd "$tools"; ./appimagetool.AppImage --appimage-extract >/dev/null)
# Use AppRun so bundled libraries are resolved without FUSE.
mkdir -p "$tools/bin"
printf '#!/bin/sh\nexec "%s/squashfs-root/AppRun" "$@"\n' "$tools" > "$tools/bin/appimagetool"
chmod +x "$tools/bin/appimagetool"
printf '%s\n' "$tools/bin" >> "$GITHUB_PATH"
printf 'SIRB_APPIMAGE_RUNTIME=%s/runtime\nAPPIMAGE_EXTRACT_AND_RUN=1\n' "$tools" >> "$GITHUB_ENV"
