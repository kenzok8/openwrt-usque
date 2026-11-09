#!/usr/bin/env python3
"""Prepare an upstream package candidate without changing the current pins."""
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

version = sys.argv[1].removeprefix('v')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    raise ValueError('Only stable upstream version tags are accepted')
root = Path(__file__).resolve().parent.parent
source = (root / 'usque/Makefile').read_text()
current = re.search(r'^PKG_VERSION:=(.+)$', source, re.M).group(1)
changed = tuple(map(int, version.split('.'))) > tuple(map(int, current.split('.')))
if os.environ.get('GITHUB_OUTPUT'):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('changed=' + str(changed).lower() + '\n')
if not changed:
    print('Upstream already matches:', version)
    raise SystemExit(0)
url = f'https://github.com/Diniboy1123/usque/releases/download/v{version}/checksums.txt'
with urllib.request.urlopen(url, timeout=30) as response:
    checksums = dict((name.lstrip('*'), digest) for digest, name in
                     (line.split(None, 1) for line in response.read().decode().splitlines() if line))
lines = []
arch = None
for line in source.splitlines():
    match = re.search(r'USQUE_ARCH:=(\w+)', line)
    if match:
        arch = match.group(1)
    if 'USQUE_HASH:=' in line:
        digest = checksums[f'usque_{version}_linux_{arch}.zip']
        if not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('Invalid upstream checksum')
        line = re.sub(r'USQUE_HASH:=\w+', 'USQUE_HASH:=' + digest, line)
    lines.append(line)
candidate = '\n'.join(lines) + '\n'
candidate = re.sub(r'^PKG_VERSION:=.+$', 'PKG_VERSION:=' + version, candidate, flags=re.M)
candidate = re.sub(r'^PKG_RELEASE:=.+$', 'PKG_RELEASE:=1', candidate, flags=re.M)
candidate = candidate.replace('upstream ' + current + ' binary', 'upstream ' + version + ' binary')
output = root / 'artifacts/upstream'
output.mkdir(parents=True, exist_ok=False)
(output / 'Makefile').write_text(candidate)
(output / 'manifest.json').write_text(json.dumps({'previous_version': current, 'candidate_version': version,
    'upstream': 'https://github.com/Diniboy1123/usque', 'checksums_url': url,
    'status': 'candidate only; SDK and runtime validation required'}, indent=2) + '\n')
print('Prepared update candidate:', version)
