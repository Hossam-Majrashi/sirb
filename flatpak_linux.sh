#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for tool in flutter flatpak flatpak-builder flock; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool. Install it before building Flatpak." >&2; exit 127; }
done
mkdir -p dist build
exec 9>build/.sirb-package.lock
flock 9
host="$(uname -m)"
version="$(python3 tool/release.py version)"
for arch in ${SIRB_LINUX_ARCH:-x64 arm64}; do
  case "$arch" in x64) fp_arch=x86_64 ;; arm64) fp_arch=aarch64 ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
  bundle="build/linux/$arch/release/bundle"
  if [[ "$host" == "$fp_arch" && "${SIRB_SKIP_BUILD:-0}" != 1 ]]; then flutter build linux --release --target-platform "linux-$arch"
  elif [[ ! -x "$bundle/sirb" ]]; then echo "No $arch cross-build on $host. Build on $fp_arch: flutter build linux --release --target-platform linux-$arch; ./flatpak_linux.sh"; continue
  fi
  python3 tool/release.py binary linux "$fp_arch" "$bundle/sirb"
  rm -rf build/flatpak-bundle; cp -a "$bundle" build/flatpak-bundle
  flatpak-builder --assumeyes --disable-rofiles-fuse --arch="$fp_arch" --user --install-deps-from=flathub --force-clean --repo="build/flatpak-repo-$arch" --default-branch=stable "build/flatpak-$arch" flatpak/com.h.sirb.json
  flatpak build-bundle --arch="$fp_arch" "build/flatpak-repo-$arch" "dist/sirb-$version-linux-$fp_arch.flatpak" com.h.sirb stable --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
done
