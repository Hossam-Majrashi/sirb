#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo 'Flutter SDK is required.' >&2; exit 127; }
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
case "$(uname -s)" in
  Linux) ./build_linux.sh; ./flatpak_linux.sh; echo 'Windows requires MSVC on Windows; macOS requires Xcode on macOS. See BUILD_NOTES.md.' ;;
  Darwin) bash tool/package_macos.sh; echo 'Linux and Windows builds require their native hosts.' ;;
  *) echo 'Use build_windows.ps1 from a Windows developer shell.' ;;
esac
