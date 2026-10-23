#!/usr/bin/env python3
"""Hermetic release regressions; does not pretend to compile other platforms."""
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

import release


def pe(path, machine):
    header = bytearray(64)
    header[:2] = b'MZ'
    struct.pack_into('<I', header, 60, 64)
    path.write_bytes(header + b'PE\0\0' + struct.pack('<H', machine))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def test_supported_inventory_and_naming(self):
        names = release.names('1.2.3')
        self.assertEqual(len(names), 23)
        self.assertIn('sirb-1.2.3-windows-arm64-setup.exe', names)
        self.assertIn('sirb-1.2.3-windows-x64-portable.zip', names)
        self.assertIn('sirb-1.2.3-linux-aarch64.AppImage.zsync', names)
        self.assertIn('sirb-1.2.3-macos-universal.dmg', names)
        for name in names:
            self.assertFalse(any(unsupported in name for unsupported in ['-armv7.', '-i686.', '-windows-x86']))

    def test_checksums_require_complete_nonempty_inventory_and_no_extras(self):
        targets = [('macos', 'arm64')]
        with self.assertRaises(ValueError):
            release.inventory(self.root, targets)
        file = self.root / next(iter(release.names(targets=targets)))
        file.touch()
        with self.assertRaises(ValueError):
            release.inventory(self.root, targets)
        file.write_bytes(b'fixture, not a compiled DMG')
        release.inventory(self.root, targets)
        sums = self.root / 'SHA256SUMS.txt'
        self.assertEqual(sums.read_text(), release.digest(file) + '  ' + file.name + '\n')
        release.inventory(self.root, targets)
        (self.root / 'old.flatpak').write_text('stale')
        with self.assertRaises(ValueError):
            release.inventory(self.root, targets)

    def test_checksums_are_stable_sorted_and_include_zsync(self):
        for name in release.names():
            (self.root / name).write_text(name)
        release.inventory(self.root)
        sums = (self.root / 'SHA256SUMS.txt').read_text()
        self.assertEqual(len(sums.splitlines()), 23)
        self.assertEqual([line.split('  ')[1] for line in sums.splitlines()], sorted(release.names()))
        self.assertNotIn('dist/', sums)

    def test_real_elf_header_not_filename_controls_architecture(self):
        path = self.root / 'sirb'
        for arch, machine in [('x86_64', 62), ('aarch64', 183)]:
            header = bytearray(64)
            header[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', header, 18, machine)
            path.write_bytes(header)
            release.binary_arch(path, 'linux', arch)
            other = 'aarch64' if arch == 'x86_64' else 'x86_64'
            with self.assertRaises(ValueError):
                release.binary_arch(path, 'linux', other)
        path.write_bytes(b'not a binary')
        with self.assertRaises(ValueError):
            release.binary_arch(path, 'linux', 'x86_64')

    def test_windows_installers_include_all_files_and_stable_guids(self):
        for arch, machine in [('x64', 0x8664), ('arm64', 0xAA64)]:
            bundle = self.root / arch
            bundle.mkdir()
            pe(bundle / 'sirb.exe', machine)
            pe(bundle / 'libcef.dll', machine)
            (bundle / 'data/nested & directory').mkdir(parents=True)
            (bundle / 'data/nested & directory/a & b.txt').write_text('payload')
            work, output = self.root / ('work-' + arch), self.root / ('out-' + arch)
            release.windows_sources(bundle, arch, work, output)
            source = (work / 'sirb.wxs').read_bytes()
            root = ET.fromstring(source)
            ns = {'w': 'http://wixtoolset.org/schemas/v4/wxs'}
            files = root.findall('.//w:File', ns)
            self.assertEqual(len(files), 3)
            ids = [node.attrib['Id'] for node in root.iter() if 'Id' in node.attrib and not node.tag.endswith('ComponentRef')]
            self.assertEqual(len(ids), len(set(ids)))
            self.assertTrue(all(node.attrib['Bitness'] == 'always64' for node in root.findall('.//w:Component', ns)))
            self.assertEqual(root.find('w:Package', ns).attrib['Scope'], 'perUser')
            self.assertIn('On="uninstall"', source.decode())
            iss = (work / 'sirb.iss').read_text()
            self.assertIn('ArchitecturesAllowed=' + ('arm64' if arch == 'arm64' else 'x64compatible'), iss)
            self.assertIn('AppId={{', iss)
            with zipfile.ZipFile(next(output.glob('*.zip'))) as archive:
                self.assertEqual(set(archive.namelist()), {'sirb.exe', 'libcef.dll', 'data/nested & directory/a & b.txt'})
            release.windows_sources(bundle, arch, work, output)
            self.assertEqual(source, (work / 'sirb.wxs').read_bytes())
            wrong = 'arm64' if arch == 'x64' else 'x64'
            with self.assertRaises(ValueError):
                release.windows_sources(bundle, wrong, work, output)

    def test_version_and_tag_validation_before_build_or_publish(self):
        (self.root / 'pubspec.yaml').write_text('version: 1.2.3+4\n')
        output = self.root / 'outputs'
        with patch.object(release, 'ROOT', self.root):
            self.assertEqual(release.version(), '1.2.3')
            args = ['release.py', 'metadata', '--github-output', str(output)]
            with patch.object(sys, 'argv', args), patch.dict(os.environ, {'GITHUB_REF_TYPE': 'tag', 'GITHUB_REF_NAME': 'v1.2.4'}):
                with self.assertRaises(ValueError):
                    release.main()
            self.assertFalse(output.exists())
            with patch.object(sys, 'argv', args), patch.dict(os.environ, {'GITHUB_REF_TYPE': 'tag', 'GITHUB_REF_NAME': 'v1.2.3'}):
                release.main()
            self.assertIn('publish=true\n', output.read_text())
            (self.root / 'pubspec.yaml').write_text('version: shell; injection\n')
            with self.assertRaises(ValueError):
                release.version()


if __name__ == '__main__':
    unittest.main()
