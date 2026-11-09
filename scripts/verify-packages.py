#!/usr/bin/env python3
"""Collect a complete SDK package set and record its immutable inputs."""
import argparse
import hashlib
import io
import json
import re
import shutil
import tarfile
from pathlib import Path


def member(archive, name, executable=False):
    entries = [item for item in archive.getmembers() if item.name.removeprefix('./') == name and item.isfile()]
    if len(entries) != 1:
        raise ValueError(f'Missing or duplicate member: {name}')
    if executable and not entries[0].mode & 0o111:
        raise ValueError(f'Executable permission is missing: {name}')
    return archive.extractfile(entries[0]).read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packages-dir', type=Path, required=True)
    parser.add_argument('--sdk', choices=['24.10', '25.12'], required=True)
    parser.add_argument('--arch', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    extension = 'ipk' if args.sdk == '24.10' else 'apk'
    manifest = {'sdk': args.sdk, 'architecture': args.arch, 'runtime_validation': 'not performed by SDK build', 'packages': {}}
    selected = []
    for package in ('usque', 'luci-app-usque'):
        makefile = (root / package / 'Makefile').read_text()
        version = re.search(r'^PKG_VERSION:=(.+)$', makefile, re.M).group(1).strip()
        release = re.search(r'^PKG_RELEASE:=(.+)$', makefile, re.M).group(1).strip()
        arch = args.arch if package == 'usque' else 'all'
        if extension == 'apk':
            # apk 文件名不带架构（SDK 产出，如 usque-4.2.1-r4.apk）；
            # 参考 honk 的做法：release 时才补 -arch（如 honk-2026.11.09-r1-x86_64.apk），
            # 这里两种都接受，架构以目录/参数为准。
            pattern = re.compile(re.escape(package) + r'[_-]' + re.escape(version) + r'-(?:r)?' + re.escape(release) + r'(?:[_-]' + re.escape(arch) + r')?' + r'\.' + extension + '$')
        else:
            # ipk 文件名带架构：usque_4.2.1-4_x86_64.ipk
            pattern = re.compile(re.escape(package) + r'[_-]' + re.escape(version) + r'-(?:r)?' + re.escape(release) + r'[_-]' + re.escape(arch) + r'\.' + extension + '$')
        paths = [p for p in args.packages_dir.glob('*.' + extension) if pattern.fullmatch(p.name)]
        if len(paths) != 1 or paths[0].stat().st_size < 1024:
            raise ValueError(f'Expected exactly one nonempty {package} {version}-r{release} for {arch}')
        path = paths[0]
        if extension == 'ipk':
            with tarfile.open(path) as outer:
                data = member(outer, 'data.tar.gz')
            with tarfile.open(fileobj=io.BytesIO(data)) as payload:
                if any('tests' in Path(item.name).parts for item in payload.getmembers()):
                    raise ValueError('Local tests included in package')
                if package == 'usque':
                    binary = member(payload, 'usr/bin/usque', executable=True)
                    elf_class, machine = (2, 62) if args.arch == 'x86_64' else (2, 183) if args.arch.startswith('aarch64') else (1, 40)
                    if binary[:4] != b'\x7fELF' or binary[4:6] != bytes((elf_class, 1)) or int.from_bytes(binary[18:20], 'little') != machine:
                        raise ValueError('Core ELF architecture does not match SDK target')
                    for source in (root / 'usque/files').glob('*.sh'):
                        if member(payload, 'usr/share/usque/' + source.name, executable=True) != source.read_bytes():
                            raise ValueError(f'Script payload drift: {source.name}')
                else:
                    for source in (root / 'luci-app-usque/htdocs/luci-static/resources/view/usque').iterdir():
                        if source.suffix == '.css' and member(payload, 'www/luci-static/resources/view/usque/' + source.name) != source.read_bytes():
                            raise ValueError('Stylesheet payload drift')
                    member(payload, 'www/luci-static/usque/logo.svg')
        selected.append(path)
        manifest['packages'][package] = {'version': version + '-r' + release, 'filename': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    args.output_dir.mkdir(parents=True, exist_ok=False)
    for path in selected:
        shutil.copyfile(path, args.output_dir / path.name)
    (args.output_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.output_dir / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in sorted(args.output_dir.iterdir()) if p.is_file()))
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
