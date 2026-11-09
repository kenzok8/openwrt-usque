#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# TUN 模式下的 LAN DNS 配套。
#
# 本机 dnsmasq 会把 LAN 的 UDP/TCP 53 抓回自己（nft 表 inet dnsmasq 的
# DNSMASQ HIJACK），再拿运营商解析器出结果。这里给选定 LAN 设备单开一条路：
# 先把目的端口改写成 5353，端口一变，那条只认 dport 53 的劫持规则就不再命中，
# 因而不必改别人的表和规则；5353 上跑的是只往隧道解析器转发的 dnsmasq 实例。
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
. /usr/share/usque/lib.sh

cmd=${1:-}
token=${2:-}
lan=${3:-}

case "$cmd" in on | off) : ;; *)
	echo 'usque: dns.sh on <token> <lan> | off <token>' >&2
	exit 1
	;;
esac

umask 077
mkdir -p /etc/usque /var/lock

section_hash() {
	sha256sum "$1" | cut -d ' ' -f 1
}

# 只导出本插件那一段，用于归属比对
snapshot_section() {
	uci export dhcp 2> /dev/null | awk -v target="'$USQUE_DNS_SECTION'" '
		/^package / { if ($0 ~ /^package dhcp;?$/) print "package dhcp"; next }
		/^config / { keep = index($0, target) ? 1 : 0; if (keep) print; next }
		keep { print }
	' > "$1"
}

section_present() {
	uci -q get "dhcp.$USQUE_DNS_SECTION" > /dev/null 2>&1
}

read_proof() {
	[ -f "$USQUE_DNS_OWNER" ] || return 1
	IFS= read -r owner_hash < "$USQUE_DNS_OWNER"
	echo "$owner_hash" | grep -Eq '^[0-9a-f]{64}$'
}

write_proof() {
	proof_file=$(mktemp /etc/usque/.dns-owner.XXXXXX)
	printf '%s\n' "$(section_hash "$1")" > "$proof_file"
	chmod 600 "$proof_file"
	mv -f "$proof_file" "$USQUE_DNS_OWNER"
}

drop_section() {
	uci -q delete "dhcp.$USQUE_DNS_SECTION" || true
	uci commit dhcp || return 1
	rm -f "$USQUE_DNS_OWNER"
	dnsmasq_reload
}

dnsmasq_reload() {
	/etc/init.d/dnsmasq reload > /dev/null 2>&1
}

dnsmasq_listening() {
	# BusyBox 的 sleep 不吃小数，按秒重试
	i=0
	while [ "$i" -lt 10 ]; do
		netstat -lnu 2> /dev/null | grep -q ":$USQUE_DNS_PORT " && return 0
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# 隧道解析器自己出网也要打标，否则会走原默认路由，等于没做
nft_dns_on() {
	nft -f - << EOF
table inet usque {
	chain dnsnat {
		type nat hook prerouting priority dstnat - 10; policy accept;
		iifname "$lan" meta nfproto ipv4 udp dport 53 redirect to :$USQUE_DNS_PORT
		iifname "$lan" meta nfproto ipv4 tcp dport 53 redirect to :$USQUE_DNS_PORT
	}
	chain dnsout {
		type route hook output priority mangle; policy accept;
		ip daddr { $USQUE_DNS_UPSTREAM, $USQUE_DNS_UPSTREAM2 } udp dport 53 meta mark set $USQUE_MARK
		ip daddr { $USQUE_DNS_UPSTREAM, $USQUE_DNS_UPSTREAM2 } tcp dport 53 meta mark set $USQUE_MARK
	}
}
EOF
}

nft_dns_off() {
	nft list table inet usque > /dev/null 2>&1 || return 0
	nft delete chain inet usque dnsnat > /dev/null 2>&1 || true
	nft delete chain inet usque dnsout > /dev/null 2>&1 || true
}

tmpdir=$(mktemp -d /tmp/usque-dns.XXXXXX)
snapshot=$tmpdir/section
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

acquire_lock
trap 'release_lock; rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ -f "$USQUE_ROUTE_STATE" ]; then
	read_route_state || {
		release_lock
		echo dns_owner_state_invalid >&2
		exit 1
	}
	if [ -n "$token" ] && [ "$state_token" != "$token" ]; then
		if [ "$cmd" = off ]; then
			release_lock
			exit 0
		fi
		release_lock
		echo dns_instance_changed >&2
		exit 1
	fi
elif [ "$cmd" = on ]; then
	release_lock
	echo dns_route_not_ready >&2
	exit 1
fi

owned=0
if section_present; then
	if read_proof; then
		snapshot_section "$snapshot" || {
			release_lock
			echo dns_write_failed >&2
			exit 1
		}
		[ "$(section_hash "$snapshot")" = "$owner_hash" ] && owned=1 || owned=0
	elif [ "$cmd" = on ]; then
		# 没有证明文件：只有确实是我们的实例（instance/port 对得上）才接手，
		# 否则视为别人的同名 section，不能覆盖
		if [ "$(uci -q get "dhcp.$USQUE_DNS_SECTION.instance")" = "$USQUE_DNS_SECTION" ] &&
			[ "$(uci -q get "dhcp.$USQUE_DNS_SECTION.port")" = "$USQUE_DNS_PORT" ]; then
			owned=1
		fi
	fi
	if [ "$owned" = 0 ] && [ "$cmd" = off ]; then
		# 同名 section 不是本插件写的，停用时保留，不替用户做主
		nft_dns_off
		release_lock
		exit 0
	fi
	if [ "$owned" = 0 ]; then
		release_lock
		echo dns_section_conflict >&2
		exit 1
	fi
fi

if [ "$cmd" = on ] && [ -n "$(uci -q changes dhcp)" ]; then
	release_lock
	echo dns_pending >&2
	exit 1
fi

case "$cmd" in
on)
	valid_ifname "$lan" || {
		release_lock
		echo dns_invalid_lan >&2
		exit 1
	}
	if ! uci set "dhcp.$USQUE_DNS_SECTION=dnsmasq" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.instance=$USQUE_DNS_SECTION" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.port=$USQUE_DNS_PORT" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.nonwildcard=1" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.localservice=1" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.noresolv=1" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.domainneeded=0" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.expandhosts=0" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.nohosts=1" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.cachesize=0" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.boguspriv=0" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.rebind_protection=0" ||
		! uci add_list "dhcp.$USQUE_DNS_SECTION.interface=$lan" ||
		! uci set "dhcp.$USQUE_DNS_SECTION.allservers=1" ||
		! uci add_list "dhcp.$USQUE_DNS_SECTION.server=$USQUE_DNS_UPSTREAM" ||
		! uci add_list "dhcp.$USQUE_DNS_SECTION.server=$USQUE_DNS_UPSTREAM2" ||
		! uci commit dhcp; then
		drop_section || true
		release_lock
		echo dns_write_failed >&2
		exit 1
	fi
	if ! dnsmasq_reload || ! dnsmasq_listening; then
		drop_section || true
		release_lock
		echo dns_resolver_failed >&2
		exit 1
	fi
	snapshot_section "$snapshot" || {
		drop_section || true
		release_lock
		echo dns_write_failed >&2
		exit 1
	}
	write_proof "$snapshot" || {
		drop_section || true
		release_lock
		echo dns_write_failed >&2
		exit 1
	}
	if ! nft_dns_on; then
		drop_section || true
		release_lock
		echo dns_firewall_failed >&2
		exit 1
	fi
	release_lock
	;;
off)
	nft_dns_off
	if [ "$owned" = 1 ]; then
		drop_section || {
			release_lock
			echo dns_write_failed >&2
			exit 1
		}
	fi
	release_lock
	;;
esac
