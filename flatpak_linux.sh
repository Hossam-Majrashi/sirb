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
for pair in 'x64:x86_64' 'arm64:aarch64'; do
  arch="${pair%%:*}"; fp_arch="${pair#*:}"; bundle="build/linux/$arch/release/bundle"
  if [[ "$host" == "$fp_arch" ]]; then flutter build linux --release --target-platform "linux-$arch"
  elif [[ ! -x "$bundle/sirb" ]]; then echo "No $arch cross-build on $host. Build on $fp_arch: flutter build linux --release --target-platform linux-$arch; ./flatpak_linux.sh"; continue
  fi
  rm -rf build/flatpak-bundle; cp -a "$bundle" build/flatpak-bundle
  flatpak-builder --arch="$fp_arch" --user --install-deps-from=flathub --force-clean --repo="build/flatpak-repo-$arch" --default-branch=stable "build/flatpak-$arch" flatpak/com.h.sirb.json
  flatpak build-bundle --arch="$fp_arch" "build/flatpak-repo-$arch" "dist/com.h.sirb-$fp_arch.flatpak" com.h.sirb stable --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
done
