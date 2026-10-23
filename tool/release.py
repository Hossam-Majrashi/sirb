#!/usr/bin/env python3
"""Release naming/inventory, architecture checks and stable Windows installer manifests.

Standard library only; no tokens, package managers or network access required.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
import subprocess
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    ('linux', 'x86_64'): ('AppImage', 'AppImage.zsync', 'deb', 'rpm', 'pkg.tar.zst', 'tar.gz', 'flatpak'),
    ('linux', 'aarch64'): ('AppImage', 'AppImage.zsync', 'deb', 'rpm', 'pkg.tar.zst', 'tar.gz', 'flatpak'),
    ('macos', 'x86_64'): ('dmg',),
    ('macos', 'arm64'): ('dmg',),
    ('macos', 'universal'): ('dmg',),
    ('windows', 'x64'): ('msi', 'setup.exe', 'portable.zip'),
    ('windows', 'arm64'): ('msi', 'setup.exe', 'portable.zip'),
}


def version():
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$', text, re.M)
    if not match:
        raise ValueError('pubspec version must be a numeric release version')
    return match[1]


def names(ver=None, targets=None):
    ver = ver or version()
    return {f'sirb-{ver}-{system}-{arch}' + ('-' if ext in ('setup.exe', 'portable.zip') else '.') + ext
            for system, arch in (targets or TARGETS)
            for ext in TARGETS[system, arch]}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(directory, targets=None):
    expected = names(targets=targets)
    actual = {p.name for p in directory.iterdir() if p.is_file() and p.name != 'SHA256SUMS.txt'}
    if actual != expected:
        raise ValueError(f'Release inventory mismatch: missing={sorted(expected-actual)}, unexpected={sorted(actual-expected)}')
    for name in expected:
        if (directory / name).stat().st_size == 0:
            raise ValueError(f'Empty artifact: {name}')
    checksums = directory / 'SHA256SUMS.txt'
    checksums.write_text(''.join(f'{digest(directory / name)}  {name}\n' for name in sorted(expected)), encoding='utf-8')
    print(f'Validated {len(expected)} artifacts; wrote {checksums}')


def binary_arch(path, system, arch):
    with path.open('rb') as stream:
        header = stream.read(64)
        if system == 'linux':
            if header[:5] != b'\x7fELF\x02' or header[5] != 1:
                raise ValueError(f'Not a 64-bit little-endian ELF: {path}')
            machine = struct.unpack_from('<H', header, 18)[0]
            expected = {'x86_64': 62, 'aarch64': 183}[arch]
        elif system == 'windows':
            if header[:2] != b'MZ':
                raise ValueError(f'Not a PE: {path}')
            stream.seek(struct.unpack_from('<I', header, 60)[0])
            signature = stream.read(6)
            if signature[:4] != b'PE\0\0':
                raise ValueError(f'Invalid PE: {path}')
            machine = struct.unpack_from('<H', signature, 4)[0]
            expected = {'x64': 0x8664, 'arm64': 0xAA64}[arch]
        else:
            raise ValueError(system)
    if machine != expected:
        raise ValueError(f'Wrong architecture in {path}: machine={machine}, expected {arch}')


def windows_sources(bundle, arch, work, output):
    """Harvest all Flutter/CEF files. Stable IDs/GUIDs survive upgrades."""
    binary_arch(bundle / 'sirb.exe', 'windows', arch)
    binary_arch(bundle / 'libcef.dll', 'windows', arch)
    files = sorted(p for p in bundle.rglob('*') if p.is_file())
    if not files:
        raise ValueError('Empty Windows payload')
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    namespace = 'http://wixtoolset.org/schemas/v4/wxs'
    ET.register_namespace('', namespace)
    def element(parent, name, **attrs):
        return ET.SubElement(parent, f'{{{namespace}}}{name}', attrs)
    def ident(prefix, text):
        return prefix + hashlib.sha256(text.encode()).hexdigest()[:24]
    def guid(text):
        return str(uuid.uuid5(uuid.NAMESPACE_URL, 'https://sirb.app/install/' + text))
    wix = ET.Element(f'{{{namespace}}}Wix')
    package = element(wix, 'Package', Name='Sirb', Manufacturer='Hossam Majrashi',
                      Version=version(), Language='1033', Scope='perUser', InstallerVersion='500',
                      UpgradeCode=guid(arch + '/upgrade'))
    element(package, 'MajorUpgrade', DowngradeErrorMessage='A newer version of Sirb is already installed.')
    element(package, 'MediaTemplate', EmbedCab='yes')
    local = element(package, 'StandardDirectory', Id='LocalAppDataFolder')
    programs = element(local, 'Directory', Id='LocalPrograms', Name='Programs')
    install = element(programs, 'Directory', Id='INSTALLFOLDER', Name='Sirb')
    directories = {'.': install}
    feature = element(package, 'Feature', Id='Main', Title='Sirb', Level='1')
    main_id = None
    for path in files:
        relative = path.relative_to(bundle)
        parent = Path('.')
        for part in relative.parts[:-1]:
            child = parent / part
            key = child.as_posix()
            if key not in directories:
                directories[key] = element(directories[parent.as_posix()], 'Directory', Id=ident('D', key), Name=part)
            parent = child
        key = relative.as_posix()
        component_id = ident('C', key)
        component = element(directories[parent.as_posix()], 'Component', Id=component_id,
                            Guid=guid(arch + '/' + key), Bitness='always64')
        file_id = ident('F', key)
        element(component, 'File', Id=file_id, Source=str(path.resolve()))
        # Per-user components need HKCU key paths and explicit directory cleanup.
        element(component, 'RegistryValue', Root='HKCU', Key='Software\\\\Sirb\\\\Components',
                Name=component_id, Type='integer', Value='1', KeyPath='yes')
        element(feature, 'ComponentRef', Id=component_id)
        if key == 'sirb.exe':
            main_id = file_id
    menu = element(package, 'StandardDirectory', Id='ProgramMenuFolder')
    shortcuts = element(menu, 'Directory', Id='SirbMenu', Name='Sirb')
    component = element(shortcuts, 'Component', Id='MenuShortcut', Guid=guid(arch + '/shortcut'), Bitness='always64')
    element(component, 'Shortcut', Id='StartMenuShortcut', Name='Sirb', Target=f'[#{main_id}]', WorkingDirectory='INSTALLFOLDER')
    element(component, 'RemoveFolder', Id='RemoveMenu', On='uninstall')
    element(component, 'RemoveFolder', Id='RemoveLocalPrograms', Directory='LocalPrograms', On='uninstall')
    for key, directory in directories.items():
        element(component, 'RemoveFolder', Id=ident('R', key), Directory=directory.attrib['Id'], On='uninstall')
    element(component, 'RegistryValue', Root='HKCU', Key='Software\\Sirb', Name='Installed', Type='integer', Value='1', KeyPath='yes')
    element(feature, 'ComponentRef', Id='MenuShortcut')
    ET.indent(wix)
    ET.ElementTree(wix).write(work / 'sirb.wxs', encoding='utf-8', xml_declaration=True)
    base = f'sirb-{version()}-windows-{arch}'
    # Inno syntax uses doubled braces for literal AppId GUIDs, not Python format expansion.
    script = f'''[Setup]
AppId={{{{{guid(arch + '/inno')}}}
AppName=Sirb
AppVersion={version()}
AppPublisher=Hossam Majrashi
DefaultDirName={{localappdata}}\\Programs\\Sirb
DefaultGroupName=Sirb
PrivilegesRequired=lowest
ArchitecturesAllowed={'arm64' if arch == 'arm64' else 'x64compatible'}
ArchitecturesInstallIn64BitMode={'arm64' if arch == 'arm64' else 'x64compatible'}
OutputDir={output.resolve()}
OutputBaseFilename={base}-setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={{app}}\\sirb.exe
[Files]
Source: "{bundle.resolve()}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\\Sirb"; Filename: "{{app}}\\sirb.exe"
'''
    (work / 'sirb.iss').write_text(script, encoding='utf-8')
    with zipfile.ZipFile(output / (base + '-portable.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(bundle))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('version')
    meta = commands.add_parser('metadata')
    meta.add_argument('--github-output', type=Path, required=True)
    sums = commands.add_parser('checksums')
    sums.add_argument('directory', type=Path)
    sums.add_argument('--system', choices=['linux', 'macos', 'windows'])
    sums.add_argument('--arch')
    check = commands.add_parser('binary')
    check.add_argument('system', choices=['linux', 'windows'])
    check.add_argument('arch')
    check.add_argument('path', type=Path)
    windows = commands.add_parser('windows')
    windows.add_argument('--arch', required=True, choices=['x64', 'arm64'])
    windows.add_argument('--bundle', required=True, type=Path)
    windows.add_argument('--work', type=Path, default=ROOT / 'build/installers')
    windows.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if args.command == 'version':
        print(version())
    elif args.command == 'metadata':
        ver = version()
        tag = 'v' + ver
        if os.environ.get('GITHUB_REF_TYPE') == 'tag' and os.environ.get('GITHUB_REF_NAME') != tag:
            raise ValueError('Release tag must match pubspec version: ' + tag)
        publish = os.environ.get('GITHUB_REF_TYPE') == 'tag' or os.environ.get('PUBLISH_RELEASE') == 'true'
        with args.github_output.open('a', encoding='utf-8') as output:
            output.write(f'version={ver}\ntag={tag}\npublish={str(publish).lower()}\n')
    elif args.command == 'checksums':
        if bool(args.system) != bool(args.arch):
            parser.error('--system and --arch must be supplied together')
        targets = [(args.system, args.arch)] if args.system else None
        inventory(args.directory, targets)
    elif args.command == 'binary':
        binary_arch(args.path, args.system, args.arch)
    elif args.command == 'windows':
        windows_sources(args.bundle, args.arch, args.work, args.output)
        base = f'sirb-{version()}-windows-{args.arch}'
        subprocess.run(['wix', 'build', str(args.work / 'sirb.wxs'), '-arch', args.arch,
                        '-o', str(args.output / (base + '.msi'))], check=True)
        iscc = os.environ.get('ISCC', 'ISCC.exe')
        subprocess.run([iscc, str(args.work / 'sirb.iss')], check=True)
        # WiX emits a debug database; it is not an installable release artifact.
        for path in args.output.glob('*.wixpdb'):
            path.unlink()
        inventory(args.output, [('windows', args.arch)])


if __name__ == '__main__':
    main()
