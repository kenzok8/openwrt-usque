#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for tool in bash sh node python3; do
	command -v "$tool" > /dev/null || {
		echo "Missing tool: $tool" >&2
		exit 1
	}
done
for path in usque/files/*.sh usque/files/usque.init; do
	sh -n "$path"
done
for js in luci-app-usque/htdocs/luci-static/resources/view/usque/*.js luci-app-usque/htdocs/luci-static/resources/usque/*.js; do
	node --check "$js"
done
python3 - << 'PY'
import ast
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path('.')
for path in root.glob('luci-app-usque/root/**/*.json'):
    json.loads(path.read_text())
for path in root.glob('scripts/*.py'):
    ast.parse(path.read_text(), filename=str(path))
ET.parse('luci-app-usque/htdocs/luci-static/usque/logo.svg')
sources = [p.read_text() for p in Path('luci-app-usque/htdocs/luci-static/resources').rglob('*.js')]
messages = set()
for source in sources:
    messages |= set(re.findall(r"_\(\s*'([^']*)'\s*\)", source))
translations = Path('luci-app-usque/po/zh-cn/usque.po').read_text()
translated = set(re.findall(r'^msgid "(.+)"$', translations, re.M))
assert messages <= translated, f'Missing UI translations: {messages - translated}'
acl = json.loads(Path('luci-app-usque/root/usr/share/rpcd/acl.d/luci-app-usque.json').read_text())['luci-app-usque']
assert acl['write']['uci'] == ['usque']
assert '/etc/usque/config.json' not in json.dumps(acl)
for group in ('read', 'write'):
    for path, permissions in acl[group]['file'].items():
        assert permissions == ['exec'], (path, permissions)
        if path.startswith('/usr/share/usque/'):
            assert (root / 'usque/files' / Path(path).name).is_file(), path
makefile = Path('usque/Makefile').read_text()
assert all(len(value) == 64 for value in re.findall(r'USQUE_HASH:=(\w+)', makefile))
assert '+flock' in makefile and '+curl' in makefile
for path in root.glob('usque/files/*.sh'):
    assert path.name in makefile, f'Runtime script not installed: {path.name}'
for path in root.glob('luci-app-usque/htdocs/luci-static/resources/view/usque/*'):
    assert path.name in Path('luci-app-usque/Makefile').read_text(), f'UI asset not installed: {path}'
print('Shell, JavaScript, JSON, SVG, translations and package declarations: PASS')
PY
if git rev-parse --verify HEAD > /dev/null 2>&1; then
	git diff --check
fi
