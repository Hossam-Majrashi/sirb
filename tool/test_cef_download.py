#!/usr/bin/env python3
"""Hermetic CMake downloader regressions; no network, C++ toolchain or CEF binary.

Run: python3 tool/test_cef_download.py
Tests Windows/Linux cache preparation and raw per-platform source validation.
"""
import hashlib
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DOWNLOAD = ROOT / 'third_party/webview_cef/third/download.cmake'
VALIDATE = DOWNLOAD.with_name('validate_cef.cmake')
VERSION = next(line.split('"')[1] for line in DOWNLOAD.read_text().splitlines()
               if line.startswith('set(CEF_VERSION '))
COMMON = ['CMakeLists.txt', 'LICENSE.txt', 'cmake/FindCEF.cmake',
          'cmake/cef_variables.cmake', 'cmake/cef_macros.cmake',
          'include/cef_app.h', 'include/cef_version.h',
          'libcef_dll/base/cef_atomic_flag.cc', 'libcef_dll/shutdown_checker.cc',
          'libcef_dll/ctocpp/views/window_ctocpp.cc',
          'libcef_dll/cpptoc/test/probe_cpptoc.h',
          'include/base/cef_atomic_flag.h', 'include/capi/cef_app_capi.h',
          'include/base/internal/probe.inc']
BINARIES = {
    'Linux': ['chrome-sandbox', 'libcef.so', 'libEGL.so', 'libGLESv2.so',
              'libvk_swiftshader.so', 'libvulkan.so.1', 'v8_context_snapshot.bin',
              'vk_swiftshader_icd.json'],
    'Windows': ['libcef.lib', 'libcef.dll', 'chrome_elf.dll', 'd3dcompiler_47.dll',
                'libEGL.dll', 'libGLESv2.dll', 'v8_context_snapshot.bin',
                'vk_swiftshader.dll', 'vk_swiftshader_icd.json', 'vulkan-1.dll'],
    'Darwin': ['Chromium Embedded Framework.framework/Chromium Embedded Framework'],
}
SOURCES = '''set(LIBCEF_SRCS
  shutdown_checker.cc
  )
set(LIBCEF_BASE_SRCS
  base/cef_atomic_flag.cc
  ../include/base/cef_atomic_flag.h
  ../include/capi/cef_app_capi.h
  ../include/base/internal/probe.inc
  )
set(LIBCEF_CTOCPP_VIEWS_SRCS
  ctocpp/views/window_ctocpp.cc
  cpptoc/test/probe_cpptoc.h
  )
set(LIBCEF_WRAPPER_SRCS_LINUX
  wrapper/linux.cc
  )
set(LIBCEF_WRAPPER_SRCS_WINDOWS
  wrapper/windows.cc
  )
set(LIBCEF_WRAPPER_SRCS_MAC
  wrapper/mac.mm
  )
'''


def put(path, text='fixture\n'):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def fixture(root, system):
    paths = COMMON.copy()
    for config in ['Release'] if system == 'Darwin' else ['Debug', 'Release']:
        paths += [f'{config}/{binary}' for binary in BINARIES[system]]
    if system != 'Darwin':
        paths += [f'Resources/{name}' for name in ['chrome_100_percent.pak',
                  'chrome_200_percent.pak', 'resources.pak', 'icudtl.dat', 'locales/en-US.pak']]
    paths.append('libcef_dll/wrapper/'+{'Linux': 'linux.cc', 'Windows': 'windows.cc', 'Darwin': 'mac.mm'}[system])
    for path in paths:
        put(root/path)
    put(root/'include/cef_version.h', f'#define CEF_VERSION "{VERSION}"\n')
    put(root/'libcef_dll/CMakeLists.txt', SOURCES)
    put(root/'cmake/cef_variables.cmake', 'if("${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "arm64")\nendif()\n')


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sirb cef tests ')
        self.addCleanup(self.temp.cleanup)
        self.tmp = pathlib.Path(self.temp.name)
        self.environment = dict(os.environ)
        self.environment.pop('SIRB_CEF_ARCHIVE_DIR', None)
        self.dest = self.tmp/'cache/cef'
        self.package = f'cef_binary_{VERSION}_linux64.tar.bz2'
        self.archive = self.tmp/self.package
        self.payload = self.tmp/'payload'/self.package.removesuffix('.tar.bz2')
        fixture(self.payload, 'Linux')
        self.pack()

    def pack(self, payload=None):
        payload = payload or self.payload
        with tarfile.open(self.archive, 'w:bz2') as archive:
            archive.add(payload, arcname=payload.name)
        self.checksum()

    def checksum(self):
        put(pathlib.Path(str(self.archive)+'.sha1'), hashlib.sha1(self.archive.read_bytes()).hexdigest())

    def script(self, system='Linux', arch='x86_64', url=None):
        script = self.tmp/f'prepare-{system}-{arch}.cmake'
        put(script, f'''cmake_minimum_required(VERSION 3.10)
set(CMAKE_SYSTEM_NAME "{system}")
set(CMAKE_SYSTEM_PROCESSOR "{arch}")
set(CMAKE_HOST_SYSTEM_PROCESSOR "{arch}")
set(CMAKE_GENERATOR_PLATFORM "{arch}")
include("{DOWNLOAD}")
set(cef_prebuilt_path "{url or self.archive.as_uri()}")
prepare_prebuilt_files("{self.dest}")
''')
        return ['cmake', '-P', str(script)]

    def run_prepare(self, success=True, **kwargs):
        result = subprocess.run(self.script(**kwargs), text=True, capture_output=True, timeout=30, env=self.environment)
        self.assertEqual(result.returncode == 0, success, result.stdout+result.stderr)
        return result.stdout+result.stderr

    def cached(self, version=None):
        fixture(self.dest, 'Linux')
        put(self.dest/'version.txt', version or self.package)
        put(self.dest/'old-cache-sentinel')

    def assert_preserved(self, version):
        self.assertEqual((self.dest/'version.txt').read_text(), version)
        self.assertTrue((self.dest/'old-cache-sentinel').is_file())

    def test_missing_sources_with_matching_stamp_repair_then_skip_download(self):
        self.cached()
        shutil.rmtree(self.dest/'libcef_dll/base')
        output = self.run_prepare()
        self.assertIn('Incomplete CEF cache', output)
        self.assertTrue((self.dest/'libcef_dll/base/cef_atomic_flag.cc').is_file())
        self.assertFalse((self.dest/'old-cache-sentinel').exists())
        self.assertFalse(pathlib.Path(str(self.dest)+'.prepare').exists())
        self.assertIn('aarch64', (self.dest/'cmake/cef_variables.cmake').read_text())
        self.assertIn('CEF cache verified', self.run_prepare(url=(self.tmp/'not-found').as_uri()))

    def test_nested_headers_sources_resources_and_empty_files_are_repaired(self):
        for path in ['include/capi/cef_app_capi.h', 'libcef_dll/ctocpp/views/window_ctocpp.cc',
                     'libcef_dll/cpptoc/test/probe_cpptoc.h', 'Resources/locales/en-US.pak',
                     'include/base/internal/probe.inc', 'Release/libcef.so']:
            with self.subTest(path=path):
                self.cached()
                (self.dest/path).unlink()
                self.assertIn('Incomplete CEF cache', self.run_prepare())
                self.assertTrue((self.dest/path).is_file())
        put(self.dest/'Release/libcef.so', '')
        self.assertIn('empty Release/libcef.so', self.run_prepare())

    def test_new_version_installs_cleanly(self):
        self.cached('old-version')
        self.run_prepare()
        self.assertEqual((self.dest/'version.txt').read_text(), self.package)
        self.assertFalse((self.dest/'old-cache-sentinel').exists())

    def test_failed_download_preserves_old_cache(self):
        self.cached('old-version')
        self.assertIn('CEF download failed', self.run_prepare(False, url=(self.tmp/'missing').as_uri()))
        self.assert_preserved('old-version')

    def test_checksum_mismatch_preserves_old_cache(self):
        self.cached('old-version')
        put(pathlib.Path(str(self.archive)+'.sha1'), '0'*40)
        self.assertIn('checksum mismatch', self.run_prepare(False))
        self.assert_preserved('old-version')

    def test_invalid_checksum_is_rejected(self):
        put(pathlib.Path(str(self.archive)+'.sha1'), '<html>CDN error</html>')
        self.assertIn('Invalid CEF checksum', self.run_prepare(False))
        self.assertFalse(self.dest.exists())

    def test_corrupt_archive_is_not_version_stamped(self):
        self.archive.write_bytes(b'not an archive')
        self.checksum()
        self.assertIn('CEF extraction failed', self.run_prepare(False))
        self.assertFalse(self.dest.exists())
        self.pack()
        self.run_prepare()
        self.assertTrue((self.dest/'version.txt').is_file())

    def test_incomplete_archive_preserves_old_cache(self):
        self.cached('old-version')
        (self.payload/'include/base/cef_atomic_flag.h').unlink()
        self.pack()
        self.assertIn('Incomplete extracted CEF distribution', self.run_prepare(False))
        self.assert_preserved('old-version')

    def test_unexpected_archive_root_is_rejected(self):
        wrong = self.tmp/'wrong-root'
        fixture(wrong, 'Linux')
        self.pack(wrong)
        self.assertIn('Unexpected CEF archive layout', self.run_prepare(False))
        self.assertFalse(self.dest.exists())

    def test_interrupted_promotion_recovers_previous_cache(self):
        self.cached()
        self.dest.rename(pathlib.Path(str(self.dest)+'.previous'))
        put(pathlib.Path(str(self.dest)+'.prepare')/'partial')
        self.assertIn('CEF cache verified', self.run_prepare(url=(self.tmp/'missing').as_uri()))
        self.assert_preserved(self.package)
        self.assertFalse(pathlib.Path(str(self.dest)+'.previous').exists())

    def test_parallel_preparations_share_a_lock(self):
        command = self.script()
        processes = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.environment)
                     for _ in range(2)]
        outputs = []
        for process in processes:
            stdout, stderr = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, stdout+stderr)
            outputs.append(stdout)
        self.assertEqual(sum('installed and verified' in s for s in outputs), 1)
        self.assertEqual(sum('CEF cache verified' in s for s in outputs), 1)

    def test_windows_arm64_preparation_uses_windows_inventory(self):
        self.package = f'cef_binary_{VERSION}_windowsarm64.tar.bz2'
        self.archive = self.tmp/self.package
        payload = self.tmp/'windows'/self.package.removesuffix('.tar.bz2')
        fixture(payload, 'Windows')
        self.pack(payload)
        self.run_prepare(system='Windows', arch='ARM64')
        self.assertEqual((self.dest/'version.txt').read_text(), self.package)
        (self.dest/'libcef_dll/wrapper/windows.cc').unlink()
        self.assertIn('Incomplete CEF cache', self.run_prepare(system='Windows', arch='ARM64'))
        digest = self.custom()
        self.run_prepare(system='Windows', arch='ARM64')
        self.assertEqual((self.dest/'version.txt').read_text(), self.package+'|sha256='+digest)

    def test_linux_arm64_package_selection(self):
        self.package = f'cef_binary_{VERSION}_linuxarm64.tar.bz2'
        self.archive = self.tmp/self.package
        payload = self.tmp/'arm64'/self.package.removesuffix('.tar.bz2')
        fixture(payload, 'Linux')
        self.pack(payload)
        self.run_prepare(arch='aarch64')
        self.assertEqual((self.dest/'version.txt').read_text(), self.package)

    def custom(self):
        self.environment['SIRB_CEF_ARCHIVE_DIR'] = str(self.tmp)
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        put(pathlib.Path(str(self.archive)+'.sha256'), digest)
        return digest

    def test_custom_bundle_replaces_official_even_at_same_version(self):
        self.cached()
        digest = self.custom()
        output = self.run_prepare(url=(self.tmp/'no-network').as_uri())
        self.assertIn('developer-supplied', output)
        self.assertEqual((self.dest/'version.txt').read_text(), self.package+'|sha256='+digest)
        self.assertIn('CEF cache verified', self.run_prepare())
        # A newly built reviewed bundle at the same version must invalidate cache.
        put(self.payload/'Release/libcef.so', 'updated codec build')
        self.pack()
        new_digest = self.custom()
        self.assertNotEqual(digest, new_digest)
        self.run_prepare()
        self.assertEqual((self.dest/'Release/libcef.so').read_text(), 'updated codec build')

    def test_custom_bundle_wrong_digest_or_version_preserves_old_cache(self):
        self.cached()
        self.custom()
        put(pathlib.Path(str(self.archive)+'.sha256'), '0'*64)
        self.assertIn('SHA-256 mismatch', self.run_prepare(False))
        self.assert_preserved(self.package)
        put(self.payload/'include/cef_version.h', '#define CEF_VERSION "wrong-version"\n')
        self.pack()
        self.custom()
        self.assertIn('CEF version mismatch', self.run_prepare(False))
        self.assert_preserved(self.package)

    def test_missing_custom_archive_or_sidecar_never_falls_back(self):
        self.cached()
        self.environment['SIRB_CEF_ARCHIVE_DIR'] = str(self.tmp/'absent')
        self.assertIn('refusing to fall back', self.run_prepare(False))
        self.assert_preserved(self.package)
        self.environment['SIRB_CEF_ARCHIVE_DIR'] = str(self.tmp)
        self.assertIn('refusing to fall back', self.run_prepare(False))
        self.assert_preserved(self.package)
        put(pathlib.Path(str(self.archive)+'.sha256'), 'untrusted invalid checksum')
        self.assertIn('Invalid custom CEF SHA-256', self.run_prepare(False))
        self.assert_preserved(self.package)

    def test_darwin_custom_preparation_and_identity_for_both_slices(self):
        for processor, suffix in [('arm64', 'macosarm64'), ('x86_64', 'macosx64')]:
            with self.subTest(processor=processor):
                self.package = f'cef_binary_{VERSION}_{suffix}.tar.bz2'
                self.archive = self.tmp/self.package
                payload = self.tmp/suffix/self.package.removesuffix('.tar.bz2')
                fixture(payload, 'Darwin')
                self.pack(payload)
                digest = self.custom()
                self.run_prepare(system='Darwin', arch=processor)
                # Identity helper is what the macOS shell fast path uses.
                command = ['cmake', f'-DCEF_IDENTITY_PACKAGE={self.package}',
                           f'-DCEF_IDENTITY_OUTPUT={self.tmp}/identity', '-P',
                           str(DOWNLOAD.with_name('custom_cef.cmake'))]
                result = subprocess.run(command, env=self.environment, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((self.tmp/'identity').read_text(), self.package+'|sha256='+digest)

    def test_platform_specific_validation_and_missing_inventory(self):
        for system in ['Linux', 'Windows', 'Darwin']:
            with self.subTest(system=system):
                root = self.tmp/system
                fixture(root, system)
                command = ['cmake', f'-DCEF_VALIDATE_ROOT={root}', f'-DCEF_VALIDATE_SYSTEM={system}', '-P', str(VALIDATE)]
                result = subprocess.run(command, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
                put(root/'libcef_dll/CMakeLists.txt', '# truncated\n')
                result = subprocess.run(command, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('unreadable wrapper source inventory', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
