#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# 只查本机包管理器里有的版本：源里没有就报空，不去 GitHub 猜。
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

manager=unknown
if command -v apk > /dev/null 2>&1; then
	manager=apk
elif command -v opkg > /dev/null 2>&1; then
	manager=opkg
fi

installed_of() {
	case "$manager" in
	apk)
		apk list -I "$1" 2> /dev/null | awk -v p="$1" '$1 ~ "^" p "-[0-9]" {
			v = $1; sub("^" p "-", "", v); print v; exit
		}'
		;;
	opkg)
		opkg status "$1" 2> /dev/null | awk '
			/^Version: / { v = $2 }
			/^Status: .* installed$/ { i = 1 }
			END { if (i) print v }
		'
		;;
	esac
}

latest_of() {
	case "$manager" in
	apk)
		apk list "$1" 2> /dev/null | awk -v p="$1" '$1 ~ "^" p "-[0-9]" {
			v = $1; sub("^" p "-", "", v); print v
		}' | sort -V | tail -n 1
		;;
	opkg)
		opkg list "$1" 2> /dev/null | awk '$1 == p { print $2 }' p="$1" | sort -V | tail -n 1
		;;
	esac
}

feed=0
for f in /etc/apk/repositories /etc/apk/repositories.d/*.list /etc/opkg/customfeeds.conf; do
	[ -f "$f" ] || continue
	grep -q 'kenzok8\|dllkids' "$f" 2> /dev/null && feed=1
done

printf '{"manager":"%s","feed":%s,"packages":[' "$manager" "$([ "$feed" = 1 ] && echo true || echo false)"
sep=
for pkg in usque luci-app-usque; do
	installed=$(installed_of "$pkg" || true)
	latest=$(latest_of "$pkg" || true)
	printf '%s{"name":"%s","installed":"%s","latest":"%s"}' "$sep" "$pkg" "$installed" "$latest"
	sep=,
done
printf ']}\n'
