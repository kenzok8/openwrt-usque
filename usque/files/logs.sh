#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# logs.sh [行数]
# 输出本插件相关的系统日志。只读 logread，不写文件、不做轮转。
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

limit=${1:-200}
case "$limit" in '' | *[!0-9]*) limit=200 ;; esac
[ "$limit" -le 500 ] || limit=500

printf '{"lines":['
sep=
# 核心自己在消息里写 UTC 时间戳，和系统日志前缀的本地时间差 8 小时；
# 前缀已经有本地时间，这里把消息里那段去掉，避免同一行两个时间。
logread 2> /dev/null | grep -E 'usque|dnsmasq.*usque_dns' | tail -n "$limit" | while IFS= read -r line; do
	line=$(printf '%s' "$line" | sed 's# [0-9]\{4\}/[0-9][0-9]/[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] UTC # #')
	line=$(printf '%s' "$line" | tr -d '\000-\010\013\014\016-\037')
	line=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
	printf '%s"%s"' "$sep" "$line"
	sep=,
done
printf ']}\n'
