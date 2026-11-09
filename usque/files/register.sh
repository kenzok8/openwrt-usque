#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
. /usr/share/usque/lib.sh
CONF=/etc/usque/config.json
LOCK=/var/lock/usque-register.lock
umask 077
mkdir -p /etc/usque /var/lock
chmod 700 /etc/usque
exec 9> "$LOCK"
flock -n 9 || {
	echo busy
	exit 1
}

if [ -f "$CONF" ] && [ "${1:-}" != force ]; then
	echo exists
	exit 2
fi

raw=$(uci -q get usque.main.device_name || true)
name=$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9._-' | cut -c1-32)
[ -n "$name" ] || name=OpenWrt
tmpdir=$(mktemp -d /etc/usque/.register.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
tmpconf=$tmpdir/config.json
if ! timeout -k 2 20 /usr/bin/usque -c "$tmpconf" register -a -n "$name" > /dev/null 2>&1; then
	echo failed
	exit 1
fi
[ -s "$tmpconf" ] || {
	echo failed
	exit 1
}
for field in id private_key access_token endpoint_v4; do
	value=$(jsonfilter -i "$tmpconf" -e "@.$field" 2> /dev/null || true)
	[ -n "$value" ] && [ "$value" != null ] || {
		echo failed
		exit 1
	}
done
endpoint=$(jsonfilter -i "$tmpconf" -e '@.endpoint_v4' 2> /dev/null || true)
valid_ipv4 "$endpoint" || {
	echo failed
	exit 1
}
chmod 600 "$tmpconf"
mv -f "$tmpconf" "$CONF"
echo ok
