#!/bin/bash
#vim:filetype=sh

show_help() {
	cat <<EOF
Usage: bash scripts/${0##*/} [-dpr]

Flutter run modes.

	-d			Debug mode.
	-p			Profile mode.
	-r			Release mode.
EOF
}

while getopts hdpr opt; do
	case $opt in
	h)
		show_help
		exit 0
		;;
	d)
		printf '%s\n' "--- Running web platform in debug mode ---"
		flutter run \
			--debug \
			--device-id web-server \
			--web-port 8000 \
			--dart-define=ENDPOINT=http://localhost:8080
		;;
	p)
		printf '%s\n' "--- Running web platform in profile mode ---"
		flutter run \
			--verbose \
			--profile \
			--device-id web-server \
			--web-port 8000 \
			--dart-define=Dart2jsOptimization=O1 \
			--dart-define=ENDPOINT=http://localhost:8080
		;;
	r)
		printf '%s\n' "--- Running web platform in release mode ---"
		flutter run \
			--release \
			--device-id web-server \
			--web-port 8000 \
			--dart-define=Dart2jsOptimization=O4 \
			--dart-define=ENDPOINT=http://localhost:8080
		;;
	*)
		show_help >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))
if [[ $# -ne 0 ]]; then
	echo >&2 "$0: unexpected argument: $1"
	exit 3
fi
