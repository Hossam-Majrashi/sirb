#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for tool in flutter fpm rpmbuild dpkg-deb tar zstd appimagetool zsyncmake python3 unshare flock llvm-strip; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool. Install it and re-run build_linux.sh." >&2; exit 127; }
done
version="$(python3 tool/release.py version)"
mkdir -p dist build
exec 9>build/.sirb-package.lock
flock 9
host="$(uname -m)"
for arch in ${SIRB_LINUX_ARCH:-x64 arm64}; do
  [[ "$arch" == x64 || "$arch" == arm64 ]] || { echo "Unsupported Linux architecture: $arch" >&2; exit 1; }
  machine=x86_64; debarch=amd64
  [[ "$arch" != arm64 ]] || { machine=aarch64; debarch=arm64; }
  bundle="build/linux/$arch/release/bundle"
  if [[ "$host" == "$machine" ]]; then
    flutter build linux --release --target-platform "linux-$arch"
  elif [[ ! -x "$bundle/sirb" ]]; then
    echo "Cannot cross-build $arch on $host. On a $machine host: flutter build linux --release --target-platform linux-$arch; then run ./build_linux.sh. No $arch outputs fabricated."
    continue
  fi
  python3 tool/release.py binary linux "$machine" "$bundle/sirb"
  stage="build/package-$arch"
  rm -rf "$stage"; mkdir -p "$stage/opt/com.h.sirb" "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/1024x1024/apps"
  cp -a "$bundle/." "$stage/opt/com.h.sirb/"
  find "$stage/opt/com.h.sirb" -type f -name '*.so*' -exec llvm-strip --strip-debug {} +
  cp LICENSE "$stage/opt/com.h.sirb/LICENSE"
  install -m755 packaging/sirb-launcher "$stage/opt/com.h.sirb/launcher"
  ln -s /opt/com.h.sirb/launcher "$stage/usr/bin/sirb"
  install -m644 packaging/com.h.sirb.desktop "$stage/usr/share/applications/"
  install -m644 assets/icon/icon.png "$stage/usr/share/icons/hicolor/1024x1024/apps/com.h.sirb.png"
  install -Dm644 assets/icon/icon128.png "$stage/usr/share/icons/hicolor/128x128/apps/com.h.sirb.png"
  install -Dm644 flatpak/com.h.sirb.metainfo.xml "$stage/usr/share/metainfo/com.h.sirb.metainfo.xml"
  common=(-s dir -n com.h.sirb -v "$version" --iteration 1 --maintainer 'Hossam.Majrashi@gmail.com' --url 'https://hossam-majrashi.github.io/Works/' --description 'Persistent Chromium desktop browser with video-aware tab management' --license Apache-2.0 -C "$stage" -f)
  fpm "${common[@]}" -t deb -a "$debarch" -d libgtk-3-0 -d libnss3 -d libnspr4 -d libasound2 -d libx11-6 -d libxcomposite1 -d libxdamage1 -d libxrandr2 -d libgbm1 -d libdrm2 -d libxkbcommon0 -d libatk1.0-0 -d libatk-bridge2.0-0 -d libpango-1.0-0 -d libcairo2 -d libgl1 -d libsqlite3-0 -d util-linux -p "dist/sirb-${version}-linux-${machine}.deb" .
  fpm "${common[@]}" -t rpm -a "$machine" -d 'libgtk-3.so.0()(64bit)' -d 'libnss3.so()(64bit)' -d 'libnspr4.so()(64bit)' -d 'libasound.so.2()(64bit)' -d 'libX11.so.6()(64bit)' -d 'libXcomposite.so.1()(64bit)' -d 'libXdamage.so.1()(64bit)' -d 'libXrandr.so.2()(64bit)' -d 'libgbm.so.1()(64bit)' -d 'libdrm.so.2()(64bit)' -d 'libxkbcommon.so.0()(64bit)' -d 'libatk-1.0.so.0()(64bit)' -d 'libatk-bridge-2.0.so.0()(64bit)' -d 'libpango-1.0.so.0()(64bit)' -d 'libcairo.so.2()(64bit)' -d 'libGL.so.1()(64bit)' -d 'libsqlite3.so.0()(64bit)' -d util-linux -p "dist/sirb-${version}-linux-${machine}.rpm" .
  archstage="build/pacman-$arch"; rm -rf "$archstage"; cp -a "$stage" "$archstage"
  {
    echo 'pkgname = com.h.sirb'; echo "pkgver = $version-1"; echo 'pkgdesc = Video-focused desktop Chromium browser'; echo "arch = $machine"; echo "builddate = $(date +%s)"; echo "size = $(du -sb "$stage" | cut -f1)"; echo 'license = Apache-2.0'
    for dep in gtk3 nss nspr alsa-lib libx11 libxcomposite libxdamage libxrandr mesa libdrm libxkbcommon at-spi2-core pango cairo sqlite util-linux; do echo "depend = $dep"; done
  } > "$archstage/.PKGINFO"
  tar --zstd -cf "dist/sirb-$version-linux-$machine.pkg.tar.zst" -C "$archstage" .PKGINFO opt usr
  tar -czf "dist/sirb-$version-linux-$machine.tar.gz" -C "$stage" opt usr
  appdir="build/Sirb-$arch.AppDir"; rm -rf "$appdir"; mkdir -p "$appdir/usr/lib/com.h.sirb"
  cp -a "$stage/opt/com.h.sirb/." "$appdir/usr/lib/com.h.sirb/"
  install -Dm644 flatpak/com.h.sirb.metainfo.xml "$appdir/usr/share/metainfo/com.h.sirb.metainfo.xml"
  install -m755 packaging/sirb-launcher "$appdir/usr/lib/com.h.sirb/launcher"
  install -m644 packaging/com.h.sirb.desktop "$appdir/com.h.sirb.desktop"
  install -m644 assets/icon/icon.png "$appdir/com.h.sirb.png"
  printf '#!/bin/sh\nHERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "$HERE/usr/lib/com.h.sirb/launcher" "$@"\n' > "$appdir/AppRun"
  chmod +x "$appdir/AppRun"
  image="sirb-$version-linux-$machine.AppImage"
  repository="${GITHUB_REPOSITORY:-Hossam-Majrashi/sirb}"
  owner="${repository%%/*}"; repo="${repository#*/}"
  runtime=()
  [[ -z "${SIRB_APPIMAGE_RUNTIME:-}" ]] || runtime=(--runtime-file "$SIRB_APPIMAGE_RUNTIME")
  ARCH="$machine" appimagetool "${runtime[@]}" -u "gh-releases-zsync|$owner|$repo|latest|sirb-*-linux-$machine.AppImage.zsync" "$appdir" "dist/$image"
  zsyncmake -u "https://github.com/$repository/releases/download/v$version/$image" -o "dist/$image.zsync" "dist/$image"
  [[ -s "dist/$image.zsync" ]] || { echo 'Missing AppImage update metadata' >&2; exit 1; }
done
echo 'Packages are in repository-root dist/. Linux ARMv7 and x86-32 are unsupported by Flutter.'
