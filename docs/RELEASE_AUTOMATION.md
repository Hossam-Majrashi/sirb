# GitHub Actions desktop builds

Workflow: [Build desktop packages](../.github/workflows/build.yml).

## Build and download

- Push to `main` or open a pull request (except Markdown-only changes): validate, build native packages, upload
  per-target Actions artifacts. Download them under **Actions → workflow run →
  Artifacts**. Artifacts expire after **5 days**.
- **Actions → Build desktop packages → Run workflow** builds the selected ref.
  Leave `publish` **false** for a development/test build.
- A complete successful run also produces `sirb-complete-<version>`, containing
  all 23 supported packages plus `SHA256SUMS.txt`.
- No CEF distribution or build directory is cached across platforms. Flutter is
  pinned to **3.47.7**, source revision
  `abaf9c523780a608bd46686fd5e53740a07077f8`. The native SDK is bootstrapped
  from source because the published SDK archive list has no Linux/Windows ARM64
  archives for this version. On Windows the batch/PowerShell bootstrap must be
  used, not MINGW's x64-only bootstrap. If native Dart is unavailable, the ARM64
  job fails rather than relabelling an x64 binary.

## Supported names

`<app>` is `sirb`; `<version>` is the numeric release version in `pubspec.yaml`
(without the `+build` suffix).

| System | Architecture suffixes | Package suffixes |
| --- | --- | --- |
| Linux | `x86_64`, `aarch64` | `.AppImage`, `.AppImage.zsync`, `.deb`, `.rpm`, `.pkg.tar.zst`, `.tar.gz`, `.flatpak` |
| macOS | `x86_64`, `arm64`, `universal` | `.dmg` |
| Windows | `x64`, `arm64` | `.msi`, `-setup.exe`, `-portable.zip` |

Examples: `sirb-1.0.1-linux-aarch64.AppImage.zsync`,
`sirb-1.0.1-macos-universal.dmg`, `sirb-1.0.1-windows-arm64-setup.exe`.

**Linux armv7/i686 and Windows x86 are not supported by the project's Flutter/CEF
stack.** There are no jobs or fabricated files for these targets. Supporting
32-bit desktop would require a different engine/toolchain, not renaming an x64
package. Native Linux ARM64 uses `ubuntu-24.04-arm`; native Windows ARM64 uses
`windows-11-arm`. Runner availability/usage limits are controlled by GitHub.

The inventory checker rejects missing, empty and unexpected/stale artifacts.
ELF/PE headers guard against wrong-architecture payloads. macOS packaging checks
all Mach-O slices and all five CEF helpers, then thins **every** native payload
for single-architecture DMGs, retaining both slices in the universal build.
These are build/architecture checks, not interactive cross-platform runtime proof.

AppImage's embedded update information targets this repository's latest release
and the matching architecture's `.zsync` file. `zsyncmake` writes the versioned
GitHub download URL. Both appimagetool 1.9.1 and the 20251108 runtime are pinned
and SHA-256 checked. Update metadata does **not** add an in-app auto-updater.

## Publishing a release

1. Review security, licensing, release notes and native test results. Official
   CEF still lacks verified H.264/AAC decoders. A successful package build does
   not fix codec availability, guarantee ad removal or validate every website.
2. Configure the macOS secrets below. The public release path requires Developer
   ID signing, notarization and stapling; it fails closed if credentials are absent.
3. Increment `pubspec.yaml`, e.g. from `1.0.0+1` to `1.0.1+2`, and commit/push.
4. Push the matching tag, e.g. `git tag v1.0.1; git push origin v1.0.1`.
   Alternatively run the workflow on that commit with `publish=true`.
5. All native jobs and tests must succeed. The collector recomputes one checksum
   file from the **exact complete inventory**, uploads to a draft release,
   verifies server asset sizes and SHA-256 digests, then publishes it as latest.

The tag must equal `v<pubspec version>` and point to this exact source commit.
An existing published release is **never overwritten**, nor is a version tag
retargeted. The manually uploaded `v1.0.0` release remains unchanged: use a new
version for the first automated release. Failed uploads remain a draft; rerunning
only the collector with the same build artifacts can resume matching uploads.
A rebuild producing different bytes must not replace the draft's assets silently.

Only the collector has `contents: write`; all builds use read-only permissions.
Publishing uses GitHub's built-in job-scoped token (`github.token`), not a PAT.
Checkout does not persist credentials. Third-party Actions are commit-pinned.

## macOS signing secrets

Under **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate **with private key** (`.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `MACOS_SIGN_IDENTITY` | Exact `Developer ID Application: … (TEAMID)` identity |
| `MACOS_NOTARY_KEY_ID` | App Store Connect API key ID |
| `MACOS_NOTARY_ISSUER_ID` | API issuer ID |
| `MACOS_NOTARY_KEY_P8_BASE64` | Base64-encoded notarization API private key (`.p8`) |

Keys are decoded only into a private temporary directory and imported into a
throwaway keychain, then deleted. Nested code is signed inside out; the app and
DMG are notarized/stapled and verified. No `--deep` signing shortcut is used.

Non-publishing CI runs use ad-hoc signing only. Those DMGs are **development
artifacts**, not notarized releases, and Gatekeeper may block them. No Gatekeeper
or sandbox disabling is added. Public macOS distribution still requires the
security review described in [BUILD_NOTES.md](../BUILD_NOTES.md).

Windows installers are currently **unsigned** (SmartScreen may warn). MSI uses
per-user installation, stable upgrade/component GUIDs and uninstall cleanup;
Inno Setup generates the matching per-user setup EXE. CI installs WiX 6.0.2 and
SHA-256-verified Inno Setup 6.7.3 rather than trusting the runner's preinstalled
compiler (some images have Inno 6.2 without ARM64 support). App-local architecture-
matched MSVC CRT DLLs are included. Choose **one** installer format, not both;
portable ZIP users need neither installer. Windows code-signing credentials and
Authenticode integration are not implemented by this change.

## Local packaging and checks

- Linux: `SIRB_LINUX_ARCH=x64 bash build_linux.sh`, then
  `SIRB_LINUX_ARCH=x64 SIRB_SKIP_BUILD=1 bash flatpak_linux.sh`.
  Use `arm64` on a native ARM64 host. Requires `zsyncmake` in addition to the
  packaging dependencies in BUILD_NOTES.md. Scripts package only available,
  architecture-validated bundles; old `dist/` files must be removed before a
  strict inventory check.
- Windows: native matching Flutter/Dart, MSVC, Python 3.11+, WiX 6.0.2 and Inno
  Setup 6.3+; `./build_windows.ps1 -Arch x64` or `-Arch arm64` on matching hosts.
  Set `ISCC` if the compiler is not on PATH. This Flutter version has **no**
  Windows `--target-platform` flag; architecture follows the native Dart ABI.
- macOS: `SIRB_MACOS_ARCH=universal bash tool/package_macos.sh` (or `x86_64` /
  `arm64`). `SIRB_RELEASE_SIGN=1` requires the six signing/notarization variables.
- Validate one target:
  `python3 tool/release.py checksums dist --system linux --arch x86_64`.
- Validate the merged release and write checksums:
  `python3 tool/release.py checksums dist`.
- Verify downloads in their directory: `sha256sum -c SHA256SUMS.txt`.
- Hermetic helper tests:
  `python3 -m unittest discover -s tool -p test_release.py -v` (eight tests,
  including mocked draft publishing and immutable published-release protection).
- CEF staging/integrity regressions: `python3 tool/test_cef_download.py` (20 tests;
  transient transfer retry uses only a loopback fixture server).
- CocoaPod/wrapper NDEBUG ABI flag checks: `ruby tool/test_cef_macos_config.rb`
  (Ruby required; no CocoaPods/macOS needed). This evaluates the podspec DSL with
  a test harness; it is not a native link/runtime test.

`tool/ci_linux_setup.sh` is explicitly for disposable GitHub runners. It enables
user namespaces for Flatpak's builder where Ubuntu AppArmor's runner policy
blocks bubblewrap. It does not modify the installed application or remove its
Chromium sandbox. Actual native CI build results must be checked in Actions;
local source/XML/header fixture tests are not native Windows/macOS build proof.
