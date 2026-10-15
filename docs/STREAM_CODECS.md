# Twitch/Kick playback and codec-enabled CEF builds

## Diagnosis, not an ad-block workaround

Twitch error #4000 has several possible causes. On the currently bundled official
CEF 149 binary we measured **H.264=false, AAC=false**, and actual local MP4
playback failed with `DEMUXER_ERROR_NO_SUPPORTED_STREAMS`. A VP9/Opus control
played successfully. Many Twitch and Kick streams require AVC/H.264 video and
AAC audio via their own MSE/HLS players, which explains why YouTube's VP9 path
can work while these streams fail.

Ad rules, `preload`, a different user agent, installing a system `ffmpeg` package,
or overriding `MediaSource.isTypeSupported()` cannot add missing decoders to
CEF. Do not spoof these APIs, replace a random `libffmpeg`/`libcef`, disable web
security, rewrite stream tokens, or block the content CDN. Native HLS and DRM
(Widevine) are separate capabilities; adding AVC/AAC does not guarantee either
of those or universal platform/account/region support.

The desktop UI now reports missing H.264/AAC on Twitch/Kick and links to media
logs. This diagnostic does **not** implement a decoder or repair playback.

## Prepare the real engine artifacts

Build or obtain **reviewed, legally distributable CEF Standard Distributions**
from the exact revision pinned in `third_party/webview_cef/third/download.cmake`:

- CEF: `149.0.4+g2f1bfd8+chromium-149.0.7827.156`
- CEF commit: `2f1bfd842a0b6a9e770b708654986b6e5f17d772`
- Chromium: `149.0.7827.156`, CEF branch `7827`
- Required GN codec options: `proprietary_codecs=true ffmpeg_branding="Chrome"`

Use the upstream CEF build procedure:
<https://bitbucket.org/chromiumembedded/cef/wiki/BranchesAndBuilding>
and the matching `tools/automate/automate-git.py` from the pinned commit. This
is a full Chromium/CEF build, requiring substantial disk, memory and hours of
build time, **not** an app rebuild or a few extra system packages. Review codec
patent/licensing and redistribution obligations before shipping binaries.

Example upstream invocation after installing the native CEF toolchain and
obtaining/reviewing the pinned automation script (Linux x64):

```bash
export GN_DEFINES='is_official_build=true proprietary_codecs=true ffmpeg_branding="Chrome"'
python3 /path/to/pinned/automate-git.py \
  --download-dir=/large-disk/cef-build --branch=7827 \
  --checkout=2f1bfd842a0b6a9e770b708654986b6e5f17d772 \
  --x64-build --no-distrib-symbols --no-distrib-docs
```

Use matching Windows/macOS hosts/toolchains for those builds. Use the upstream
`--arm64-build` option for Arm64 where supported. Produce full Standard
Distributions with sources, headers, **Debug and Release** runtime, matching
resources/locales/snapshots and licenses; do not use minimal/client-only
packages. Sirb rebuilds its C++ wrapper from those same headers. The upstream
commands are guidance, **not a completed codec-enabled build on this host**.

## Supply bundles to all desktop build paths

Set `SIRB_CEF_ARCHIVE_DIR` to a trusted local artifact directory. Expected names
are `cef_binary_<CEF_VERSION>_<target>.tar.bz2` with these targets:

| Build | Target suffix |
|---|---|
| Linux x64 | `linux64` |
| Linux Arm64 | `linuxarm64` |
| Windows x64 | `windows64` |
| Windows Arm64 | `windowsarm64` |
| macOS Intel | `macosx64` |
| macOS Apple Silicon | `macosarm64` |

Each archive must contain exactly its matching `cef_binary_<version>_<target>/`
root directory and a sibling `<archive>.sha256` containing only the 64-character
SHA-256 digest (plus optional whitespace). For example:

```bash
archive='/trusted/cef/cef_binary_149.0.4+g2f1bfd8+chromium-149.0.7827.156_linux64.tar.bz2'
sha256sum "$archive" | awk '{print $1}' > "$archive.sha256"
export SIRB_CEF_ARCHIVE_DIR=/trusted/cef
bash ./build_linux.sh
```

Windows PowerShell:

```powershell
$env:SIRB_CEF_ARCHIVE_DIR = 'D:\trusted\cef'
$archive = Join-Path $env:SIRB_CEF_ARCHIVE_DIR 'cef_binary_149.0.4+g2f1bfd8+chromium-149.0.7827.156_windows64.tar.bz2'
(Get-FileHash -Algorithm SHA256 $archive).Hash | Set-Content -Encoding ascii "$archive.sha256"
powershell -ExecutionPolicy Bypass -File build_windows.ps1
```

macOS (the directory must hold **both** per-architecture bundles and sidecars
for a universal build):

```bash
export SIRB_CEF_ARCHIVE_DIR=/trusted/cef
cd macos
WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release pod install
cd ..
WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release flutter build macos --release
```

Keep this environment selection for subsequent builds; without it the default
source is the official codec-limited distribution again. The CMake Linux/Windows
and CocoaPods macOS paths share the same selection/checksum/version/staging
logic. Source digests participate in both cache identities, preventing an old
official build from silently winning over the requested bundle at the same
version. A configured missing archive/sidecar, bad digest, wrong CEF header
version or incomplete distribution fails without falling back or replacing the
existing cache. Headers are verified structurally, but binaries still require
runtime/ABI testing and a trusted producer; checksums do not prove codecs or
supply-chain trust. No unreviewed third-party codec binary is downloaded by this
project and none is supplied by this change.

## Required playback verification before claiming a fix

Start the rebuilt Sirb with an **isolated profile**, open one HTTP(S) tab, and
explicitly enable loopback-only testing CDP with
`SIRB_CEF_SWITCHES=remote-debugging-port=9241`. Never enable CDP on normal user
launches. Python needs `websocket-client`; the fixture generator needs `ffmpeg`:

```bash
python3 tool/verify_stream_codecs.py --port 9241 --require-h264-aac \
  --output build/stream-codec-evidence
```

This gate requires truthful H.264 and AAC MSE support **and actual advancing
native fragmented MP4 and MSE-decoded frames**, alongside a VP9/Opus control.
It writes `result.json` and fails if the engine still cannot decode AVC/AAC.
Without `--require-h264-aac` it is an observational diagnostic, not a passing
codec-release claim. Do not run it on a user's existing browsing session: it
navigates one tab and restores its URL, not its unsaved page state.

Then test real Twitch/Kick live streams, VODs and clips with accounts/logged-out,
shield on/off, pause/resume, seeking and fullscreen on **each** native platform.
A local fixture is not a live-service test, and codec support is necessary for
many streams but does not establish network availability, DRM or ad removal.

At the time of this change **no codec-enabled binary was available or built**.
The official binary remains unable to pass the playback gate. Integrating a
compatible codec-enabled distribution and passing native/live tests is still
required to finish the actual Twitch/Kick playback repair.
