# Build and runtime notes

APP_NAME=Sirb; APP_ID=com.h.sirb; version comes from pubspec.yaml. Only desktop platforms are targets. dist/ is the repository-root output directory.

## Prerequisites and commands

Common: Flutter >=3.47 (installed here: 3.47.7, Dart 3.13.5), network for pub.dev and the pinned CEF 149 standard distributions. `flutter pub get; flutter gen-l10n; dart run icons_launcher:create; flutter analyze; flutter test`.

| Target | Supported architectures | Complete command | Build host |
|---|---|---|---|
| Linux | x64 / Arm64 | `flutter build linux --release --target-platform linux-x64` / `flutter build linux --release --target-platform linux-arm64`; `./build_linux.sh` | Matching Linux host; clang/C++20, CMake, ninja, pkg-config, GTK3/Xi/OpenGL development libraries |
| Flatpak | x86_64 / aarch64 | `./flatpak_linux.sh`; `flatpak install --user dist/com.h.sirb-x86_64.flatpak` | Matching Linux host, flatpak-builder, Flathub org.freedesktop.Platform/Sdk 25.08 and Electron2.BaseApp 25.08 (Zypak) |
| Windows | x64 / Arm64 | `powershell -ExecutionPolicy Bypass -File build_windows.ps1`; individually `flutter build windows --release --target-platform windows-x64` / `windows-arm64` | Windows 10+, Visual Studio 2022 Desktop development with C++, matching MSVC ARM64 tools, CMake, Windows SDK |
| macOS | x64 / Arm64 universal | `cd macos; WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release pod install; cd ..; WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release flutter build macos --release`; `./build_desktop.sh` | macOS >=12, Xcode command-line tools, CMake/ninja, CocoaPods; sign CEF helpers/frameworks before notarization |

No desktop ARMv7 or x86-32 outputs: unsupported by official Flutter. Android/iOS/web are not targets. Linux x64 cannot build macOS/Windows or produce native Arm64 Flutter bundles without a matching host or properly configured sysroot/toolchain; scripts explicitly report this rather than manufacturing artifacts. Prebuilt Arm64 bundles can be copied into build/linux/arm64/release/bundle for packaging on x64.

Linux packaging needs fpm, rpmbuild, dpkg-deb, tar, zstd and appimagetool. `./build_linux.sh` produces .rpm, .deb, .pkg.tar.zst, .tar.gz and AppImage for each available supported architecture. Debian/RPM dependency names are native to their package families; Arch metadata lists its own dependency names. The portable payload includes CEF, Flutter, desktop launcher and icon; GTK3/NSS/audio/OpenGL system libraries remain runtime dependencies. Use a compatible GTK3 distribution or Flatpak for a fixed userspace.

## Sandbox

The fork removes upstream's unconditional `--no-sandbox`, unsafe `--disable-web-security` and relaxed SameSite behavior on Linux. Normal Linux/AppImage uses Chromium's user-namespace sandbox (`--disable-setuid-sandbox`); the launcher runs `unshare -Ur true` and fails closed with a clear explanation when the distribution blocks user namespaces. It never falls back to `--no-sandbox`. AppImage read-only mounts cannot provide a root-owned SUID helper, so this does not rely on chmod 4755 inside an image. Flatpak runs through Zypak from Electron2.BaseApp, with `ZYPAK_CEF_LIBRARY_PATH` pointing at the bundled libcef.so, and D-Bus access to org.freedesktop.Flatpak for child sandbox spawning. Installed Flatpak is required for testing; `flatpak-builder --run` does not validate Zypak's installed-app spawning.

The upstream Windows/macOS CEF distributions are linked without platform sandbox integration; their CEF sandbox remains disabled and this is a documented security limitation, not an assertion of sandbox parity. macOS App Sandbox is disabled for the bundled multiprocess CEF helpers, with explicit JIT entitlements. Do not distribute without security review, code signing and macOS notarization.

## Resource controls

Linux CPU affinity uses libc sched_getaffinity to respect cpusets, then sched_setaffinity on every existing thread before launching CEF; descendants inherit it. Linux strict RAM relaunches into `systemd-run --user --scope -p MemoryMax=<bytes>` and verifies memory.max. The availability probe checks a real transient memory-limited scope. Flatpak disables hard RAM because no user-manager delegation is assumed. Windows applies affinity and Job Object process-tree limits; >64-core processor-group machines disable the affinity selector instead of pretending that a single mask covers all groups. GPU selection applies before relaunch (PRIME env on Linux; HKCU DirectX UserGpuPreferences on Windows). Game mode resolves Automatic to the discrete GPU only when acceleration is enabled and a selectable integrated/discrete pair is detected; it does not overwrite an explicit choice. Windows reapplies the launch preference before starting CEF children as well as before restart. On NVIDIA hybrid Wayland desktops with an available DISPLAY, CEF uses X11/XWayland for native game windows to avoid cross-GPU dmabuf import failures; explicit developer Ozone choices are retained. Preference changes require restart, not migration of a running WebGL/WebGPU context. macOS affinity/GPU/hard RAM selectors are unavailable; soft sleeping remains active.

## Codec licensing

Official CEF binaries cannot be presumed to include H.264/AAC or Widevine. No proprietary codec support is advertised. VP9/AV1/Opus and an HLS H.264/AAC fixture are separate runtime probes; see verification output when available. To add licensed H.264/AAC support, build the matching CEF/Chromium source with `proprietary_codecs=true ffmpeg_branding="Chrome"` in GN_DEFINES, comply with patent/licensing obligations, and replace all three platform distributions with matching-version binaries and wrappers. Native HLS support is not assumed; MSE-based HLS playback also requires supported audio/video codecs. Server-side ads and DRM streams are not guaranteed supported.

## Verification on this host

Results and external tool/hardware blockers are recorded after final verification in VERIFICATION.md. Cross-platform compilation still requires native Windows/macOS hosts; absence of those hosts is not a substitute for building them in CI.
