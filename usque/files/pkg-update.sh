#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# pkg-update.sh start|log
# 从本机已配置的软件源升级本插件。只认包管理器里的版本，不去 GitHub 拉东西。
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin

LOG=/tmp/luci-app-usque-update.log
STATE=/tmp/luci-app-usque-update.state
LOCK=/tmp/luci-app-usque-update.lock
PACKAGES="usque luci-app-usque"

manager=unknown
if command -v apk > /dev/null 2>&1; then
	manager=apk
elif command -v opkg > /dev/null 2>&1; then
	manager=opkg
fi

read_state() {
	cat "$STATE" 2> /dev/null || echo idle
}

job_running() {
	command -v pgrep > /dev/null 2>&1 || return 1
	pgrep -f '\.usque-update-[0-9]+' > /dev/null 2>&1
}

case "${1:-log}" in
log)
	state=$(read_state)
	running=false
	if [ "$state" = running ]; then
		if job_running; then
			running=true
		else
			# 后台任务没了却没落盘，按中断处理，别让页面一直转
			state=interrupted
			printf '%s\n' "$state" > "$STATE"
		fi
	fi
	printf '{"running":%s,"state":"%s","log":[' "$running" "$state"
	sep=
	if [ -f "$LOG" ]; then
		while IFS= read -r line; do
			line=$(printf '%s' "$line" | tr -d '\000-\010\013\014\016-\037')
			line=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
			printf '%s"%s"' "$sep" "$line"
			sep=,
		done << EOF
$(tail -n 200 "$LOG")
EOF
	fi
	printf ']}\n'
	exit 0
	;;
start) : ;;
__run) : ;;
*)
	echo 'usque: pkg-update.sh start|log' >&2
	exit 1
	;;
esac

if [ "$1" = start ]; then
	command -v flock > /dev/null 2>&1 && {
		exec 9> "$LOCK"
		flock -n 9 || {
			echo busy
			exit 1
		}
	}
	service_was_running=false
	/etc/init.d/usque running > /dev/null 2>&1 && service_was_running=true
	# 升级会替换这个脚本本身，先复制到 /tmp 再执行
	self="/tmp/.usque-update-$$"
	cp "$0" "$self" 2> /dev/null || self=$0
	printf 'running\n' > "$STATE"
	sh "$self" __run "$service_was_running" > /dev/null 2>&1 &
	echo started
	exit 0
fi

# __run：后台真正执行升级
was_running=${2:-false}
set +e
: > "$LOG"
{
	echo 'usque: 先停止服务，避免替换正在运行的核心'
	/etc/init.d/usque stop
	case "$manager" in
	apk)
		echo '$ apk update'
		apk update
		printf '$ apk add --upgrade %s\n' "$PACKAGES"
		# shellcheck disable=SC2086
		apk add --upgrade $PACKAGES
		;;
	opkg)
		echo '$ opkg update'
		opkg update
		printf '$ opkg install %s\n' "$PACKAGES"
		# shellcheck disable=SC2086
		opkg install $PACKAGES
		;;
	*)
		echo '找不到 apk 或 opkg，无法升级'
		exit 1
		;;
	esac
} >> "$LOG" 2>&1
code=$?
if [ "$was_running" = true ] && /etc/init.d/usque enabled; then
	echo 'usque: 重新启动服务' >> "$LOG"
	/etc/init.d/usque start >> "$LOG" 2>&1
fi
if [ "$code" = 0 ]; then
	printf 'done\n' > "$STATE"
else
	printf 'failed:%s\n' "$code" > "$STATE"
fi
rm -f "$0"
exit 0
