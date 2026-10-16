#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# UI tests with screenshots (ArtemisUITests): every screen with the demo PCs, upright and in
# landscape, at the default and the largest accessibility text size, in light and dark mode;
# then a stream start and exit, the remote desktop's touch controls against the demo desktop
# (DesktopTests: each gesture and the input events it sends), and the app icon on the home screen.
#
#   SIM=<udid> Scripts/ui-tests.sh            (or the booted Simulator)
#   APPEARANCES="dark" Scripts/ui-tests.sh    one appearance only
#   ONLY=testStreamStartsAndReturns Scripts/ui-tests.sh
#   ONLY=HomeScreenIconTests Scripts/ui-tests.sh   the app icon on the home screen
#   ONLY=DesktopTests Scripts/ui-tests.sh          the touch controls (or DesktopTests/testGesturesUpright)
#   LIVE_HOST=<name>@<address> ONLY=LiveHostTests Scripts/ui-tests.sh   a real host: it shows up and
#                                             opens (games, or a PIN that the test cancels)
#
# Screenshots: build/ui-tests/shots/<appearance>-<orientation>-<text size>-<n>-<screen>.png.
# Logs: build/ui-tests/<appearance>.log. Exit code: the first failing xcodebuild's.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${SIM:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}"
[[ -n "$SIM" ]] || { echo "no booted Simulator (set SIM=<udid>)" >&2; exit 2; }
OUT="$PWD/build/ui-tests"
DD="${DERIVED_DATA:-$OUT/dd}"
rm -rf "$OUT/shots" && mkdir -p "$OUT/shots"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
# A help link opened in an earlier run would leave a "◀ Safari" in the status bar
xcrun simctl terminate "$SIM" com.apple.mobilesafari 2>/dev/null || true

xcodebuild build-for-testing -project Moonlight.xcodeproj -scheme ArtemisUITests -scmProvider system \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" > "$OUT/build.log" 2>&1 \
  || { grep -E "error:" "$OUT/build.log" | head -20; exit 1; }

ORIGINAL="$(xcrun simctl ui "$SIM" appearance)"
trap 'xcrun simctl ui "$SIM" appearance "$ORIGINAL" >/dev/null 2>&1 || true' EXIT
status=0
for appearance in ${APPEARANCES:-light dark}; do
  xcrun simctl ui "$SIM" appearance "$appearance"
  case "${ONLY:-}" in
    *Tests*) ONLY_ARGS=(-only-testing:"ArtemisUITests/$ONLY") ;;
    "") ONLY_ARGS=(-only-testing:ArtemisUITests/ScreenshotTests -only-testing:ArtemisUITests/DesktopTests -only-testing:ArtemisUITests/HomeScreenIconTests) ;;
    *) ONLY_ARGS=(-only-testing:"ArtemisUITests/ScreenshotTests/$ONLY") ;;
  esac
  TEST_RUNNER_ARTEMIS_APPEARANCE="$appearance" TEST_RUNNER_ARTEMIS_SHOT_DIR="$OUT/shots" \
  TEST_RUNNER_ARTEMIS_LIVE_HOST="${LIVE_HOST:-}" \
    xcodebuild test-without-building -project Moonlight.xcodeproj -scheme ArtemisUITests \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" -collect-test-diagnostics never \
      "${ONLY_ARGS[@]}" > "$OUT/$appearance.log" 2>&1 || { rc=$?; [[ $status == 0 ]] && status=$rc; }
  echo "== $appearance"
  grep -E "error:|Test Case .*(passed|failed)|\*\* TEST" "$OUT/$appearance.log" | sed 's/^.*error: //' | tail -20
done
echo "$(ls "$OUT/shots" | wc -l | tr -d ' ') screenshots in $OUT/shots"
exit $status
