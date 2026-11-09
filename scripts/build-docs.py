#!/usr/bin/env python3
"""Build the small Usque field guide from project metadata."""
import html
import json
import re
import shutil
from pathlib import Path

root = Path(__file__).resolve().parent.parent
site = json.loads((root / 'docs/site.json').read_text())
metadata = (root / 'luci-app-usque/Makefile').read_text()
version = re.search(r'^PKG_VERSION:=(.+)$', metadata, re.M).group(1) + '-r' + re.search(r'^PKG_RELEASE:=(.+)$', metadata, re.M).group(1)
output = root / 'artifacts/docs'
output.mkdir(parents=True, exist_ok=True)
esc = html.escape
navigation = ''.join(f'<a href="#{esc(s["id"])}">{i:02d} / {esc(s["title"])}</a>' for i, s in enumerate(site['sections'], 1))
sections = ''.join(f'<section id="{esc(s["id"])}"><p class="eyebrow">{i:02d} / GUIDE</p><h2>{esc(s["title"])}</h2><p class="intro">{esc(s["intro"])}</p><ul>'+''.join('<li>'+esc(item)+'</li>' for item in s['items'])+'</ul></section>' for i,s in enumerate(site['sections'],1))
page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(site['name'])} 使用指南</title><link rel="icon" href="logo.svg"><link rel="stylesheet" href="guide.css"><body><a class="skip" href="#content">跳到正文</a><header><a class="brand" href="./"><img src="logo.svg" width="34" height="34" alt="">Usque <small>使用指南</small></a><button id="menu" aria-expanded="false" aria-controls="navigation">目录</button><button id="theme" aria-label="切换深浅色">深浅色</button><a href="https://github.com/{esc(site['repository'])}">GitHub ↗</a></header><div class="shell"><aside id="navigation"><label for="search">查找使用说明</label><input id="search" type="search" placeholder="搜索路由、注册、DNS…"><nav>{navigation}</nav><p id="no-results" hidden>没有匹配内容，请尝试其他关键词。</p><small>LuCI {esc(version)}</small></aside><main id="content"><div class="opening"><p class="eyebrow">OPENWRT / WARP / MASQUE</p><h1>连接之外，<br>看清流量的去向。</h1><p>{esc(site['description'])}</p></div>{sections}<footer>上游核心由 Diniboy1123/usque 提供，遵循 MIT；本仓库 LuCI 与文档采用 GPL-3.0-only。</footer></main></div><script src="guide.js"></script></body></html>'''
(output / 'index.html').write_text(page)
(output / '404.html').write_text(f'<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>未找到页面 · Usque</title><link rel="stylesheet" href="{esc(site["base"])}guide.css"><body><main class="not-found"><p class="eyebrow">404 / USQUE</p><h1>这条路径没有内容。</h1><a href="{esc(site["base"])}">回到使用指南 →</a></main></body></html>')
for name in ('guide.css','guide.js'):
    shutil.copyfile(root / 'docs' / name, output / name)
shutil.copyfile(root / 'luci-app-usque/htdocs/luci-static/usque/logo.svg', output / 'logo.svg')
(output / '.nojekyll').touch()
print('Built Usque documentation:', output)
