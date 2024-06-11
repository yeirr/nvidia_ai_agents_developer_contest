#!/bin/bash
#vim:filetype=sh

show_help() {
	cat <<EOF
Usage: bash scripts/${0##*/} [-pr]

Flutter build modes.

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
	p)
		printf '%s\n' "--- Building web platform in profile mode ---"

		flutter clean

		# Insert build number, build name refers to version in 'pubspec.yaml'.
		FLUTTER_BUILD_NUMBER=$(date +%s)

		flutter build web \
			--suppress-analytics \
			--tree-shake-icons \
			--profile \
			--pwa-strategy none \
			--web-renderer canvaskit \
			--web-resources-cdn \
			--source-maps \
			--build-number="$FLUTTER_BUILD_NUMBER" \
			--dart-define=ExtraFrontEndOptions=--verbosity=error \
			--dart-define=DebugShowMaterialGrid=false \
			--dart-define=DebugShowCheckedModeBanner=false \
			--dart-define=DebugShowSemanticsDebugger=false \
			--dart-define=ShowPerformanceOverlay=false \
			--dart-define=FLUTTER_WEB_USE_SKIA=true \
			--dart-define=FLUTTER_WEB_USE_EXPERIMENTAL_CANVAS_TEXT=true \
			--dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/ \
			--dart-define=ENDPOINT=http://localhost:8080

		printf '%s\n' "--- Generating JSON serialization code ---"
		flutter pub run build_runner build --release --delete-conflicting-outputs

		printf '%s\n' "--- Run python -m http.server 8000 --directory build/web ---"
		printf '%s\n' "--- Open Chrome mobile browser(>=v119 for WebAssembly support) ---"
		printf '%s\n' "--- Navigate to 'http://localhost:8000' ---"
		;;
	r)
		printf '%s\n' "--- Building web platform in release mode with Wasm target ---"

		flutter clean

		FLUTTER_BUILD_NUMBER=$(date +%s)

		flutter build web \
			--wasm \
			--build-number="$FLUTTER_BUILD_NUMBER" \
			--dart-define=ENDPOINT=http://localhost:8080

		printf '%s\n' "--- Generating JSON serialization code ---"
		flutter pub run build_runner build --release --delete-conflicting-outputs

		printf '%s\n' "--- Removing canvaskit profiling from build directory ---"
		rm -rf build/web/canvaskit/profiling

		printf '%s\n' "--- Run dhttpd '--headers=Cross-Origin-Embedder-Policy=credentialless;Cross-Origin-Opener-Policy=same-origin' --port=8000 --path=build/web  ---"
		printf '%s\n' "--- Open Chrome mobile browser(>=v119 for WebAssembly support) ---"
		printf '%s\n' "--- Navigate to 'http://localhost:8000' ---"
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
