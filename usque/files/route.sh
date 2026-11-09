#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
. /usr/share/usque/lib.sh
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
cmd=${1:-}
token=${2:-}
iface=${3:-}
lan=${4:-}
route_lan=${5:-0}
endpoint=${6:-}
route_dns=${7:-0}

valid_route() {
	safe_token "$token" && valid_ifname "$iface" && [ "$iface" != lo ] && [ "$iface" != br-lan ] || return 1
	case "$route_lan" in 0 | 1) : ;; *) return 1 ;; esac
	case "$route_dns" in 0 | 1) : ;; *) return 1 ;; esac
	[ "$route_dns" = 1 ] && [ "$route_lan" != 1 ] && return 1
	if [ "$route_lan" = 1 ]; then
		valid_ifname "$lan" && [ "$lan" != "$iface" ] && valid_ipv4 "$endpoint" || return 1
	fi
}

check_devices() {
	if [ -e "/sys/class/net/$iface" ]; then
		ip -d link show dev "$iface" 2> /dev/null | grep -Eq '(^|[[:space:]])tun([[:space:]]|$)' || return 1
	fi
	if [ "$route_lan" = 1 ]; then [ -d "/sys/class/net/$lan" ]; fi
}

owner_cleanup_locked() {
	[ -f "$USQUE_ROUTE_STATE" ] || return 0
	read_route_state || {
		echo owner_state_invalid >&2
		return 1
	}
	[ "$state_token" = "$1" ] || return 0
	cleanup_token=$state_token
	while ip -4 rule del fwmark "$USQUE_MARK" lookup "$USQUE_TABLE" priority "$USQUE_PRIO" 2> /dev/null; do :; done
	while ip -4 rule del oif "$state_iface" lookup "$USQUE_TABLE" priority "$USQUE_PRIO_OIF" 2> /dev/null; do :; done
	ip -4 route del blackhole default metric 42760 table "$USQUE_TABLE" 2> /dev/null || true
	ip -4 route del default dev "$state_iface" metric 10 table "$USQUE_TABLE" 2> /dev/null || true
	if nft list table inet usque 2> /dev/null | grep -q 'comment "managed-by-usque"'; then nft delete table inet usque; fi
	if [ "$(cat "$USQUE_INSTANCE" 2> /dev/null || true)" = "$state_token" ]; then rm -f "$USQUE_INSTANCE"; fi
	rm -f "$USQUE_ROUTE_STATE"
	cleanup_fw=$state_route_lan
	cleanup_dns=$state_route_dns
}

# 防火墙和 DNS 都要在持锁期间之外调用，否则会自己等自己的路由锁
own_cleanup_outside_lock() {
	[ "${cleanup_dns:-0}" = 1 ] && /usr/share/usque/dns.sh off "${cleanup_token:-}" || true
	[ "${cleanup_fw:-0}" = 1 ] && /usr/share/usque/fw.sh off "${cleanup_token:-}" || true
}

# 状态文件丢了也要能收拾自己留下的东西：表 257、标记 0x7573 和 25700/25701
# 优先级都是本插件独占的，启动时如果被占会直接报冲突，不会误删。
sweep_orphans() {
	ip -4 rule del priority "$USQUE_PRIO" > /dev/null 2>&1 || true
	ip -4 rule del priority "$USQUE_PRIO_OIF" > /dev/null 2>&1 || true
	ip -4 route del blackhole default metric 42760 table "$USQUE_TABLE" > /dev/null 2>&1 || true
	ip -4 route del default dev "$iface" metric 10 table "$USQUE_TABLE" > /dev/null 2>&1 || true
	if nft list table inet usque 2> /dev/null | grep -q 'comment "managed-by-usque"'; then nft delete table inet usque; fi
	rm -f "$USQUE_ROUTE_STATE"
}

case "$cmd" in
prepare)
	valid_route || {
		echo invalid_route_config >&2
		exit 1
	}
	check_devices || {
		echo device_conflict >&2
		exit 1
	}
	mkdir -p /var/run/usque
	cleanup_fw=0
	cleanup_dns=0
	acquire_lock
	if [ -f "$USQUE_ROUTE_STATE" ]; then
		read_route_state || {
			release_lock
			echo owner_state_invalid >&2
			exit 1
		}
		owner_cleanup_locked "$state_token"
	fi
	rules=$(ip -4 rule show)
	if printf '%s\n' "$rules" | grep -Eq "fwmark (${USQUE_MARK}|0x7573)|(^|[[:space:]])25700:|(^|[[:space:]])25701:"; then
		release_lock
		echo route_rule_conflict >&2
		exit 1
	fi
	if [ -n "$(ip -4 route show table "$USQUE_TABLE")" ]; then
		release_lock
		echo route_table_conflict >&2
		exit 1
	fi
	if nft list table inet usque > /dev/null 2>&1; then
		if nft list table inet usque | grep -q 'comment "managed-by-usque"'; then
			nft delete table inet usque
		elif [ "$route_lan" = 1 ]; then
			release_lock
			echo nft_conflict >&2
			exit 1
		fi
	fi
	tmp="$USQUE_ROUTE_STATE.$$"
	printf '%s %s %s %s %s %s\n' "$token" "$iface" "${lan:-br-lan}" "$route_lan" "${endpoint:-0.0.0.0}" "$route_dns" > "$tmp"
	chmod 600 "$tmp"
	mv -f "$tmp" "$USQUE_ROUTE_STATE"
	ip -4 route add blackhole default metric 42760 table "$USQUE_TABLE"
	[ "$route_lan" = 1 ] && ip -4 rule add fwmark "$USQUE_MARK" lookup "$USQUE_TABLE" priority "$USQUE_PRIO"

	ip -4 rule add oif "$iface" lookup "$USQUE_TABLE" priority "$USQUE_PRIO_OIF"
	release_lock
	if [ "$route_lan" = 1 ]; then
		if ! /usr/share/usque/fw.sh on "$iface" "$token"; then
			acquire_lock
			owner_cleanup_locked "$token"
			release_lock
			/usr/share/usque/fw.sh off "$token" || true
			exit 1
		fi
		acquire_lock
		if ! valid_instance "$token" || ! read_route_state || [ "$state_token" != "$token" ]; then
			owner_cleanup_locked "$token"
			release_lock
			/usr/share/usque/fw.sh off "$token" || true
			exit 1
		fi
		nft -f - << EOF
table inet usque {
 comment "managed-by-usque"
 chain prerouting {
  type filter hook prerouting priority mangle; policy accept;
  iifname "$lan" ip daddr { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, $endpoint } return
  meta nfproto ipv4 iifname "$lan" meta mark set $USQUE_MARK
 }
}
EOF
		release_lock
	fi
	if [ "$route_dns" = 1 ] && ! /usr/share/usque/dns.sh on "$token" "$lan"; then
		acquire_lock
		owner_cleanup_locked "$token"
		release_lock
		/usr/share/usque/dns.sh off "$token" || true
		/usr/share/usque/fw.sh off "$token" || true
		exit 1
	fi
	;;
run)
	valid_route || exit 1
	while valid_instance "$token"; do
		acquire_lock
		if ! read_route_state || [ "$state_token" != "$token" ]; then
			release_lock
			exit 0
		fi
		if ! valid_instance "$token"; then
			owner_cleanup_locked "$token"
			release_lock
			own_cleanup_outside_lock
			exit 0
		fi
		if [ -d "/sys/class/net/$iface" ]; then
			ip -4 route replace default dev "$iface" metric 10 table "$USQUE_TABLE" 2> /dev/null || true
		else
			ip -4 route del default dev "$iface" metric 10 table "$USQUE_TABLE" 2> /dev/null || true
		fi
		release_lock
		sleep 2
	done
	acquire_lock
	if read_route_state && [ "$state_token" = "$token" ]; then
		owner_cleanup_locked "$token"
		release_lock
		own_cleanup_outside_lock
	else release_lock; fi
	;;
stop)
	stop_token=$token
	cleanup_fw=0
	cleanup_dns=0
	acquire_lock
	if [ -f "$USQUE_ROUTE_STATE" ]; then
		read_route_state
		[ -z "$stop_token" ] && stop_token=$state_token
		owner_cleanup_locked "$stop_token"
	else
		sweep_orphans
	fi
	release_lock
	own_cleanup_outside_lock
	# 状态文件丢失时，防火墙和 DNS 配置靠归属证明清，不能留着
	[ "${cleanup_fw:-0}" = 1 ] || /usr/share/usque/fw.sh off || true
	[ "${cleanup_dns:-0}" = 1 ] || /usr/share/usque/dns.sh off || true
	;;
*) exit 1 ;;
esac
