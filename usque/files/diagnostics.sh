#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# 一次探测三个目标：Cloudflare WARP 自身、境外站点（YouTube，走隧道）、境内站点（字节跳动，直连对照）。
# 三个探测并行执行，总耗时约等于最慢的那个。
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
. /usr/share/usque/lib.sh

TMP=$(mktemp -d /tmp/usque-probe.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
	printf '{"ok":false,"warp":"unknown","plus":false,"error":"%s","targets":[]}\n' "$1"
	exit 0
}

read_core() {
	service_json=$(ubus call service list '{"name":"usque"}' 2> /dev/null || true)
	core_running=$(printf '%s' "$service_json" | jsonfilter -e '@.usque.instances.core.running' 2> /dev/null || true)
	core_pid=$(printf '%s' "$service_json" | jsonfilter -e '@.usque.instances.core.pid' 2> /dev/null || true)
	case "$core_pid" in '' | *[!0-9]*) core_pid= ;; esac
}

# curl 的秒数换成毫秒；拿不到就留空
to_ms() {
	[ -n "$1" ] || return 1
	awk -v t="$1" 'BEGIN { printf "%d", t * 1000 }'
}

read_core
[ "$core_running" = true ] && [ -n "$core_pid" ] || fail service_not_running
start_pid=$core_pid

mode=$(uci -q get usque.main.mode 2> /dev/null || echo unknown)
case "$mode" in
socks)
	bind=$(uci -q get usque.main.bind 2> /dev/null || echo 127.0.0.1)
	port=$(uci -q get usque.main.port 2> /dev/null || echo 1080)
	valid_bind "$bind" 2> /dev/null || fail invalid_config
	valid_port "$port" 2> /dev/null || fail invalid_config
	port=$(normalize_port "$port")
	case "$bind" in 0.0.0.0) bind=127.0.0.1 ;; ::) bind=::1 ;; esac
	case "$bind" in *:*) proxy="[$bind]:$port" ;; *) proxy="$bind:$port" ;; esac
	CURL="curl --socks5-hostname $proxy"
	;;
tun)
	iface=$(uci -q get usque.main.ifname 2> /dev/null || echo usque)
	valid_ifname "$iface" || fail invalid_config
	[ -d "/sys/class/net/$iface" ] || fail tun_missing
	[ -f "$USQUE_ROUTE_STATE" ] && read_route_state && valid_instance "$state_token" && [ "$state_iface" = "$iface" ] || fail route_not_ready
	CURL="curl --interface $iface"
	;;
*) fail invalid_mode ;;
esac

(
	# shellcheck disable=SC2086
	out=$($CURL -4 -sS -o "$TMP/warp.trace" --max-time 10 -w '%{http_code} %{time_total}' \
		https://www.cloudflare.com/cdn-cgi/trace 2> /dev/null) || out=
	total=${out#* }
	warp=$(sed -n 's/^warp=\([A-Za-z0-9_-]*\)$/\1/p' "$TMP/warp.trace" 2> /dev/null | head -n 1 || true)
	case "$warp" in on | plus | off) printf '%s' "$warp" > "$TMP/warp.state" ;; *) printf 'unknown' > "$TMP/warp.state" ;; esac
	to_ms "$total" > "$TMP/warp.ms" 2> /dev/null || true
) &

(
	# shellcheck disable=SC2086
	out=$($CURL -4 -sS -o /dev/null --max-time 8 -w '%{http_code} %{time_total}' https://www.youtube.com/ 2> /dev/null) || out=
	code=${out%% *}
	total=${out#* }
	case "$code" in '' | 000) : ;; *)
		printf '%s' "$code" > "$TMP/youtube.code"
		to_ms "$total" > "$TMP/youtube.ms" 2> /dev/null || true
		;;
	esac
) &

(
	# 境内站点走直连，用来判断本地网络本身是否正常，不走隧道
	out=$(curl -4 -sS -o /dev/null --max-time 8 -w '%{http_code} %{time_total}' https://www.bytedance.com/ 2> /dev/null) || out=
	code=${out%% *}
	total=${out#* }
	case "$code" in '' | 000) : ;; *)
		printf '%s' "$code" > "$TMP/domestic.code"
		to_ms "$total" > "$TMP/domestic.ms" 2> /dev/null || true
		;;
	esac
) &

wait

read_core
[ "$core_running" = true ] && [ "$core_pid" = "$start_pid" ] || fail service_changed

warp=$(cat "$TMP/warp.state" 2> /dev/null || echo unknown)
case "$warp" in on | plus | off) : ;; *) warp=unknown ;; esac
plus=false
[ "$warp" = plus ] && plus=true

target_json() {
	id=$1
	code=$(cat "$TMP/$id.code" 2> /dev/null || true)
	ms=$(cat "$TMP/$id.ms" 2> /dev/null || true)
	ok=false
	if [ -n "$code" ] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then ok=true; fi
	[ -n "$ms" ] || ms=null
	printf '{"id":"%s","ok":%s,"code":"%s","ms":%s}' "$id" "$ok" "$code" "$ms"
}

warp_json() {
	ms=$(cat "$TMP/warp.ms" 2> /dev/null || true)
	ok=false
	case "$warp" in on | plus) ok=true ;; esac
	[ -n "$ms" ] || ms=null
	printf '{"id":"warp","ok":%s,"code":"%s","ms":%s}' "$ok" "$warp" "$ms"
}

case "$warp" in on | plus) probe_ok=true ;; *) probe_ok=false ;; esac

printf '{"ok":%s,"warp":"%s","plus":%s,"error":"","targets":[%s,%s,%s]}\n' \
	"$probe_ok" "$warp" "$plus" \
	"$(warp_json)" "$(target_json youtube)" "$(target_json domestic)"
