#!/usr/bin/env bash
# Configure APT only on disposable GitHub runners, never on installed app hosts.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Run only on a GitHub Actions runner' >&2; exit 1; }
# Azure's HTTP Ubuntu mirror can throttle large dependency downloads enough to
# exhaust setup timeouts. Use the same signed Ubuntu archive over HTTPS instead.
# ARM's ports.ubuntu.com and all unrelated vendor repositories remain unchanged.
sudo python3 - <<'PY'
from pathlib import Path
source = Path('/etc/apt/sources.list.d/ubuntu.sources')
if source.exists():
    old = source.read_text()
    new = old.replace('http://azure.archive.ubuntu.com/ubuntu', 'https://archive.ubuntu.com/ubuntu')
    new = new.replace('https://azure.archive.ubuntu.com/ubuntu', 'https://archive.ubuntu.com/ubuntu')
    if new != old:
        source.write_text(new)
        print('Using official Ubuntu HTTPS archive for CI dependencies')
PY
sudo tee /etc/apt/apt.conf.d/80sirb-ci >/dev/null <<'APT'
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
APT
sudo apt-get update
