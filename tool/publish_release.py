#!/usr/bin/env python3
"""Publish a complete Actions build using only the job-scoped GH_TOKEN.

Never overwrite an existing published release or retarget a version tag.
Failed uploads leave a draft that the same commit can safely resume.
"""
import json
import os
from pathlib import Path
import subprocess

from release import digest, inventory, version


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def api(path):
    return json.loads(gh('api', path))


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or not os.environ.get('GH_TOKEN'):
        raise SystemExit('Publish only from GitHub Actions with the built-in GH_TOKEN')
    directory = Path('dist')
    inventory(directory)
    repo = os.environ['GITHUB_REPOSITORY']
    commit = gh('api', f'repos/{repo}/commits/{os.environ["GITHUB_SHA"]}').strip()
    commit = json.loads(commit)['sha']
    ver = version()
    tag = 'v' + ver
    # List matching refs without relying on an ignored/ambiguous HTTP 404.
    refs = api(f'repos/{repo}/git/matching-refs/tags/{tag}')
    ref = next((r for r in refs if r['ref'] == 'refs/tags/' + tag), None)
    if ref:
        obj = ref['object']
        while obj['type'] == 'tag':
            obj = api(f'repos/{repo}/git/tags/{obj["sha"]}')['object']
        if obj['type'] != 'commit' or obj['sha'] != commit:
            raise SystemExit('Version tag points to a different commit. Bump pubspec.yaml before publishing.')
    else:
        gh('api', '--method', 'POST', f'repos/{repo}/git/refs', '-f', 'ref=refs/tags/' + tag, '-f', 'sha=' + commit)
    releases = api(f'repos/{repo}/releases?per_page=100')
    release = next((r for r in releases if r['tag_name'] == tag), None)
    if release and not release['draft']:
        raise SystemExit('Release already published; refusing to replace its binaries. Bump pubspec.yaml.')
    if not release:
        notes = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'sirb-release-notes.md'
        notes.write_text(f'''Sirb {ver} — desktop builds from {commit}.

Linux x86_64/aarch64: AppImage + zsync, DEB, RPM, Arch, tar.gz, Flatpak.
macOS Intel/Apple Silicon/universal: Developer ID signed and notarized DMGs.
Windows x64/ARM64: MSI, setup EXE, portable ZIP (unsigned Windows packages).

Verify downloads using SHA256SUMS.txt. Install only one Windows package format.
Linux armv7/i686 and Windows x86 are unsupported by this Flutter/CEF stack.
Official CEF H.264/AAC decoder limitations remain unchanged. No universal ad-free guarantee.
''', encoding='utf-8')
        # Use the POST response directly; draft lookup by tag can return 404.
        release = json.loads(gh(
            'api', '--method', 'POST', f'repos/{repo}/releases',
            '-f', 'tag_name=' + tag, '-f', 'target_commitish=' + commit,
            '-f', 'name=Sirb ' + ver, '-F', 'draft=true',
            '-f', 'body=' + notes.read_text(encoding='utf-8'),
        ))
    expected = {p.name: p for p in directory.iterdir() if p.is_file()}
    assets = api(release['assets_url'].replace('https://api.github.com/', '', 1))
    for asset in assets:
        path = expected.get(asset['name'])
        if not path or asset['state'] != 'uploaded' or asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + digest(path):
            raise SystemExit('Existing draft contains a mismatched asset: ' + asset['name'])
    uploaded = {a['name'] for a in assets}
    for name, path in sorted(expected.items()):
        if name not in uploaded:
            subprocess.run(['gh', 'release', 'upload', tag, str(path), '--repo', repo], check=True)
    release = api(f'repos/{repo}/releases/{release["id"]}')
    if {a['name'] for a in release['assets']} != set(expected):
        raise SystemExit('Incomplete uploaded release')
    for asset in release['assets']:
        path = expected[asset['name']]
        if asset['state'] != 'uploaded' or asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + digest(path):
            raise SystemExit('Server checksum mismatch: ' + asset['name'])
    gh('api', '--method', 'PATCH', f'repos/{repo}/releases/{release["id"]}', '-F', 'draft=false', '-f', 'make_latest=true')
    print('Published: https://github.com/' + repo + '/releases/tag/' + tag)


if __name__ == '__main__':
    main()
