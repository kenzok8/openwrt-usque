#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
. /usr/share/usque/lib.sh
CONF=/etc/usque/config.json
registered=false
running=false
tun_present=false
route_ready=false
enabled=false
version=
mode=unknown
error=
lan_routing=false
dns_routing=false
pid=0
ui_version=$(tr -cd '0-9A-Za-z._+-' < /usr/share/luci-app-usque/version 2> /dev/null || true)

if [ -f "$CONF" ]; then
	id=$(jsonfilter -i "$CONF" -e '@.id' 2> /dev/null || true)
	key=$(jsonfilter -i "$CONF" -e '@.private_key' 2> /dev/null || true)
	token=$(jsonfilter -i "$CONF" -e '@.access_token' 2> /dev/null || true)
	endpoint=$(jsonfilter -i "$CONF" -e '@.endpoint_v4' 2> /dev/null || true)
	if [ -n "$id" ] && [ -n "$key" ] && [ -n "$token" ] && [ -n "$endpoint" ] && [ "$id" != null ] && [ "$key" != null ] && [ "$token" != null ] && valid_ipv4 "$endpoint"; then registered=true; else error=account_invalid; fi
else
	error=account_missing
fi

uci -q get usque.main.enabled 2> /dev/null | grep -qx 1 && enabled=true || true
mode=$(uci -q get usque.main.mode 2> /dev/null || echo unknown)
case "$mode" in socks | tun) : ;; *)
	mode=unknown
	if [ -z "$error" ]; then error=invalid_mode; fi
	;;
esac
uci -q get usque.main.route_lan 2> /dev/null | grep -qx 1 && lan_routing=true || true
# 版本由包写入文件；页面每 5 秒轮询一次，不能每次都去启动核心
version=$(tr -cd '0-9A-Za-z._+-' < /usr/share/usque/version 2> /dev/null || true)
endpoint_used=$(uci -q get usque.main.endpoint 2> /dev/null || true)
valid_ipv4 "${endpoint_used:-0}" 2> /dev/null || endpoint_used=$(jsonfilter -i "$CONF" -e '@.endpoint_v4' 2> /dev/null || true)
if [ -z "$version" ]; then
	raw=$(/usr/bin/usque -c '' version 2> /dev/null | sed -n 's/^usque version: //p' | head -n 1 || true)
	version=$(printf '%s' "$raw" | tr -cd '0-9A-Za-z._+-')
fi

service_json=$(ubus call service list '{"name":"usque"}' 2> /dev/null || true)
core_running=$(printf '%s' "$service_json" | jsonfilter -e '@.usque.instances.core.running' 2> /dev/null || true)
core_pid=$(printf '%s' "$service_json" | jsonfilter -e '@.usque.instances.core.pid' 2> /dev/null || true)
[ "$core_running" = true ] && running=true || true
case "$core_pid" in '' | *[!0-9]*) : ;; *) pid=$core_pid ;; esac
if [ "$mode" = tun ]; then
	ifname=$(uci -q get usque.main.ifname 2> /dev/null || echo usque)
	[ -d "/sys/class/net/$ifname" ] && tun_present=true || true
	if [ "$running" = true ] && [ "$tun_present" = true ] && ip -4 route show table 257 | grep -q "default dev $ifname"; then route_ready=true; fi
fi
if [ "$mode" = tun ] && [ "$running" = true ] && [ "$tun_present" != true ]; then error=tun_missing; fi

# DNS 接管只在服务真的跑起来时才算数
if [ "$running" = true ] && [ "$lan_routing" = true ] &&
	uci -q get usque.main.route_dns 2> /dev/null | grep -qx 1 &&
	[ "$(uci -q get "dhcp.$USQUE_DNS_SECTION.instance")" = "$USQUE_DNS_SECTION" ] &&
	[ "$(uci -q get "dhcp.$USQUE_DNS_SECTION.port")" = "$USQUE_DNS_PORT" ]; then
	dns_routing=true
fi
if [ -s /var/run/usque/error ]; then
	last_error=$(cat /var/run/usque/error)
	case "$last_error" in account_missing | account_invalid | invalid_mode | invalid_interface | invalid_bind | invalid_port | route_failed | firewall_failed | lan_zone_mismatch | dns_conflict | dns_failed | invalid_endpoint) error=$last_error ;; esac
fi
printf '{"registered":%s,"running":%s,"pid":%s,"version":"%s","ui_version":"%s","mode":"%s","tun_present":%s,"route_ready":%s,"lan_routing":%s,"dns_routing":%s,"enabled":%s,"error":"%s","endpoint":"%s"}\n' "$registered" "$running" "$pid" "$version" "$ui_version" "$mode" "$tun_present" "$route_ready" "$lan_routing" "$dns_routing" "$enabled" "$error" "$endpoint_used"
