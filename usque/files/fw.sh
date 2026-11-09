#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
. /usr/share/usque/lib.sh

cmd=${1:-}
iface=${2:-}
token=${3:-}
if [ "$cmd" = off ]; then
	token=${2:-}
	iface=
fi
case "$cmd" in on | off) : ;; *)
	echo 'usque: fw.sh on <ifname> | off' >&2
	exit 1
	;;
esac
[ "$cmd" != on ] || [ -n "$token" ] || exit 1

OWNER=/etc/usque/firewall-owner
umask 077
mkdir -p /var/lock /etc/usque
exec 8> /var/lock/usque-fw.lock
flock -w 10 8 || exit 1
route_lock=0
release_route_lock() {
	if [ "$route_lock" = 1 ]; then
		release_lock
		route_lock=0
	fi
}
trap release_route_lock EXIT

acquire_lock
if [ -f "$USQUE_ROUTE_STATE" ]; then
	read_route_state || {
		release_lock
		exit 1
	}
	if [ -n "$token" ] && [ "$state_token" != "$token" ]; then
		release_lock
		[ "$cmd" = off ] && exit 0
		exit 1
	fi
	if [ "$cmd" = off ] && [ -z "$token" ]; then
		# 没给 token 时按状态文件里的实例收尾；section 归属仍由证明哈希把关
		token=$state_token
	fi
elif [ "$cmd" = on ]; then
	release_lock
	exit 1
fi
route_lock=1

has_section() { uci -q get "firewall.$1" > /dev/null 2>&1; }
sections_exist() { has_section usque_zone || has_section usque_lan; }

if [ "$cmd" = off ] && ! sections_exist && [ ! -f "$OWNER" ]; then exit 0; fi
if [ -n "$(uci -q changes firewall)" ]; then
	echo firewall_pending >&2
	exit 1
fi

snapshot_sections() {
	uci export firewall | awk '
		/^package / { if ($0 ~ /^package firewall;?$/) print "package firewall"; next }
		/^config / {
			quote = sprintf("%c", 39)
			keep = index($0, quote "usque_zone" quote) || index($0, quote "usque_lan" quote)
			if (keep) print
			next
		}
		keep { print }
	' > "$1"
	grep -qx 'package firewall' "$1"
}

section_hash() {
	sha256sum "$1" | cut -d ' ' -f 1
}

read_proof() {
	[ -f "$OWNER" ] || return 1
	IFS= read -r owner_hash < "$OWNER"
	echo "$owner_hash" | grep -Eq '^[0-9a-f]{64}$'
}

write_proof() {
	hash=$(section_hash "$proof_snapshot")
	proof_tmp=$(mktemp /etc/usque/.firewall-owner.XXXXXX)
	printf '%s\n' "$hash" > "$proof_tmp"
	chmod 600 "$proof_tmp"
	mv -f "$proof_tmp" "$OWNER"
}

restore_snapshot() {
	uci -q delete firewall.usque_lan > /dev/null 2>&1 || true
	uci -q delete firewall.usque_zone > /dev/null 2>&1 || true
	if grep -q '^config ' "$snapshot"; then
		uci -m import firewall < "$snapshot" || return 1
	fi
	uci commit firewall || return 1
	fw4 reload > /dev/null 2>&1 || return 1
}

tmpdir=$(mktemp -d /tmp/usque-firewall.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
snapshot=$tmpdir/sections
trap 'release_route_lock; rm -rf "$tmpdir"' EXIT
trap 'exit 1' HUP INT TERM
snapshot_sections "$snapshot" || {
	echo snapshot_failed >&2
	exit 1
}
proof_snapshot=$tmpdir/current

if read_proof; then
	current_hash=$(section_hash "$snapshot")
	[ "$owner_hash" = "$current_hash" ] || {
		echo section_conflict >&2
		exit 1
	}
elif sections_exist; then
	echo section_conflict >&2
	exit 1
fi

case "$cmd" in
on)
	valid_ifname "$iface" || exit 1
	if ! uci set firewall.usque_zone=zone ||
		! uci set firewall.usque_zone.name=usque ||
		! uci set firewall.usque_zone.device="$iface" ||
		! uci set firewall.usque_zone.input=REJECT ||
		! uci set firewall.usque_zone.output=ACCEPT ||
		! uci set firewall.usque_zone.forward=REJECT ||
		! uci set firewall.usque_zone.masq=1 ||
		! uci set firewall.usque_zone.mtu_fix=1 ||
		! uci set firewall.usque_zone.family=ipv4 ||
		! uci set firewall.usque_lan=forwarding ||
		! uci set firewall.usque_lan.src=lan ||
		! uci set firewall.usque_lan.dest=usque; then
		restore_snapshot || true
		exit 1
	fi
	if ! uci commit firewall || ! fw4 reload; then
		restore_snapshot || true
		exit 1
	fi
	if ! snapshot_sections "$proof_snapshot" || ! write_proof; then
		restore_snapshot || true
		exit 1
	fi
	;;
off)
	if ! sections_exist; then
		[ -f "$OWNER" ] && {
			echo section_conflict >&2
			exit 1
		}
		exit 0
	fi
	uci -q delete firewall.usque_lan > /dev/null 2>&1 || true
	uci -q delete firewall.usque_zone > /dev/null 2>&1 || true
	if ! uci commit firewall || ! fw4 reload; then
		restore_snapshot || true
		exit 1
	fi
	rm -f "$OWNER"
	;;
esac
