#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only

USQUE_MARK=0x7573
USQUE_TABLE=257
USQUE_PRIO=25700
USQUE_PRIO_OIF=25701
USQUE_CONF=/etc/usque/config.json
USQUE_RUNTIME_CONF=/var/run/usque/config.json
USQUE_LOCK=/var/lock/usque.lock
USQUE_INSTANCE=/var/run/usque/instance
USQUE_ROUTE_STATE=/var/run/usque/route-state
USQUE_DNS_SECTION=usque_dns
USQUE_DNS_OWNER=/etc/usque/dns-owner
USQUE_DNS_PORT=5353
USQUE_DNS_UPSTREAM=1.1.1.1
USQUE_DNS_UPSTREAM2=1.0.0.1

valid_ipv4() {
	ip=$1
	o=
	case "$ip" in '' | *[!0-9.]*) return 1 ;; esac
	echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
	oldifs=$IFS
	IFS=.
	# shellcheck disable=SC2086
	set -- $ip
	IFS=$oldifs
	[ "$#" -eq 4 ] || return 1
	for o in "$@"; do
		# Drop leading zeros so "08" is not read as octal.
		o=$(printf '%s' "$o" | sed 's/^0*\(.\)/\1/')
		[ -n "$o" ] || return 1
		[ "$o" -le 255 ] 2> /dev/null || return 1
	done
}

valid_ifname() {
	case "$1" in '' | *[!A-Za-z0-9._-]*) return 1 ;; esac
	echo "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9._-]{0,14}$'
}

lan_in_zone() {
	local zone_index zone_name devices networks network device
	zone_index=0
	while uci -q get "firewall.@zone[$zone_index]" > /dev/null 2>&1; do
		zone_name=$(uci -q get "firewall.@zone[$zone_index].name" || true)
		if [ "$zone_name" = lan ]; then
			devices=$(uci -q get "firewall.@zone[$zone_index].device" || true)
			for device in $devices; do
				[ "$device" != "$1" ] || return 0
			done
			networks=$(uci -q get "firewall.@zone[$zone_index].network" || true)
			for network in $networks; do
				device=$(ubus call "network.interface.$network" status 2> /dev/null | jsonfilter -e '@.l3_device' 2> /dev/null || true)
				[ "$device" != "$1" ] || return 0
			done
		fi
		zone_index=$((zone_index + 1))
	done
	return 1
}

valid_port() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	echo "$1" | grep -Eq '^[0-9]+$' || return 1
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

normalize_port() {
	printf '%s\n' "$1" | sed 's/^0*//'
}

valid_bind() {
	valid_ipv4 "$1" && return 0
	case "$1" in '' | *[!0-9A-Fa-f:]*) return 1 ;; esac
	echo "$1" | grep -Eq '^[0-9A-Fa-f:]+$' || return 1
	echo "$1" | grep -q ':'
}

acquire_lock() {
	mkdir -p /var/lock
	exec 9> "$USQUE_LOCK"
	flock -w 10 9 || {
		echo "usque: route lock busy" >&2
		exit 1
	}
}

release_lock() {
	flock -u 9 2> /dev/null || true
	exec 9>&-
}

valid_instance() {
	[ -n "${1:-}" ] && [ -f "$USQUE_INSTANCE" ] && [ "$(cat "$USQUE_INSTANCE" 2> /dev/null)" = "$1" ]
}

read_route_state() {
	[ -f "$USQUE_ROUTE_STATE" ] || return 1
	oldifs=$IFS
	IFS=' ' read -r state_token state_iface state_lan state_route_lan state_endpoint state_route_dns < "$USQUE_ROUTE_STATE"
	IFS=$oldifs
	safe_token "$state_token" && valid_ifname "$state_iface" && valid_ifname "$state_lan" || return 1
	case "$state_route_lan" in 0 | 1) : ;; *) return 1 ;; esac
	case "${state_route_dns:-0}" in '' | 0) state_route_dns=0 ;; 1) : ;; *) return 1 ;; esac
	if [ "$state_route_lan" = 1 ]; then valid_ipv4 "$state_endpoint" || return 1; fi
	[ "$state_route_dns" = 1 ] && [ "$state_route_lan" != 1 ] && return 1
	return 0
}

safe_token() {
	case "$1" in '' | *[!A-Za-z0-9_-]*) return 1 ;; esac
}
