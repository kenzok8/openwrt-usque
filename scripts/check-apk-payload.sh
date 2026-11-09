#!/usr/bin/env bash
set -euo pipefail
packages=${1:?package directory required}
feed=${2:?source directory required}
expected_arch=${3:?package architecture required}
tool=staging_dir/host/bin/apk
if [ ! -x "$tool" ]; then
	tool=$(command -v apk || true)
fi
[ -n "$tool" ] && [ -x "$tool" ] || {
	echo 'SDK apk tool is missing' >&2
	exit 1
}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
count=0
for package in "$packages"/*.apk; do
	[ -f "$package" ] || continue
	case "$(basename "$package")" in
	usque-* | luci-app-usque-*) ;;
	*) continue ;;
	esac
	output="$work/$count"
	mkdir -p "$output"
	"$tool" extract --allow-untrusted --no-chown --destination "$output" "$package"
	if [ -f "$output/usr/bin/usque" ]; then
		test -x "$output/usr/bin/usque"
		case "$expected_arch" in
		x86_64) expected_machine=3e00 ;;
		aarch64*) expected_machine=b700 ;;
		arm*) expected_machine=2800 ;;
		*)
			echo 'Unsupported verification target' >&2
			exit 1
			;;
		esac
		machine=$(dd if="$output/usr/bin/usque" bs=1 skip=18 count=2 2> /dev/null | od -An -tx1 | tr -d ' \n')
		[ "$machine" = "$expected_machine" ] || {
			echo 'Wrong core ELF architecture' >&2
			exit 1
		}
		for source in "$feed"/usque/files/*.sh; do
			test -x "$output/usr/share/usque/$(basename "$source")"
			cmp "$source" "$output/usr/share/usque/$(basename "$source")"
		done
		cmp "$feed/usque/files/usque.init" "$output/etc/init.d/usque"
		test -s "$output/usr/share/licenses/usque/LICENSE.md"
	else
		cmp "$feed/luci-app-usque/htdocs/luci-static/resources/view/usque/usque.css" "$output/www/luci-static/resources/view/usque/usque.css"
		test -s "$output/www/luci-static/resources/view/usque/overview.js"
		cmp "$feed/luci-app-usque/htdocs/luci-static/usque/logo.svg" "$output/www/luci-static/usque/logo.svg"
	fi
	if find "$output" -type d -name tests -print -quit | grep -q .; then
		echo 'Local tests were included in a package' >&2
		exit 1
	fi
	count=$((count + 1))
done
[ "$count" -eq 2 ] || {
	echo "Expected two APKs, found $count" >&2
	exit 1
}
echo 'APK payloads match package sources'
