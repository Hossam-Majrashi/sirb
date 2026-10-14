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
  Darwin) command -v pod >/dev/null || { echo 'CocoaPods is required.' >&2; exit 127; }; (cd macos; WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release pod install); WEBVIEW_CEF_MACOS_ARCH=universal CEF_WRAPPER_BUILD_TYPE=Release flutter build macos --release; mkdir -p dist; ditto -c -k --keepParent build/macos/Build/Products/Release/Sirb.app dist/Sirb-macos-universal.zip; echo 'Linux and Windows builds require their native hosts.' ;;
  *) echo 'Use build_windows.ps1 from a Windows developer shell.' ;;
esac
