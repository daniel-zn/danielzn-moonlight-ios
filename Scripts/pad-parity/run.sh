#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Stick and D-pad parity with RetroPlay's PSP pad (docs/TOUCH.md, "Sticks and D-pad"): builds
# RetroPlay's own touch code (PadHitTesting.swift and PadTouchSurface.swift, as they are in its
# repository) and Artemis's (Artemis/Desktop/PadHitTesting.swift, PadTouch.swift) into one Mac
# Catalyst tool, plays the same touch traces on both and compares every step.
#
#   RETROPLAY=<path to the RetroPlay repository> Scripts/pad-parity/run.sh [out.csv]
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"
RETROPLAY="${RETROPLAY:?set RETROPLAY to the RetroPlay repository}"
RP_CORE="$RETROPLAY/App/Sources/RetroPlayCore/Play/PadHitTesting.swift"
RP_TOUCH="$RETROPLAY/App/Sources/RetroPlayApp/Controls/PadTouchSurface.swift"
RP_CONTROLS="$RETROPLAY/App/Sources/RetroPlayApp/Controls/PadControls.swift"
RP_MODEL="$RETROPLAY/App/Sources/RetroPlayApp/Controls/PadInputModel.swift"
OUT="${1:-$PWD/pad-parity.csv}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Artemis's PadHitTesting.swift is RetroPlay's, less `public` and its own header
if ! diff <(sed -e '1d' -e 's/public //' "$RP_CORE") <(sed -n '/^import Foundation/,$p' "$REPO/Artemis/Desktop/PadHitTesting.swift"); then
  echo "FAIL: Artemis/Desktop/PadHitTesting.swift differs from RetroPlay's" >&2; exit 1
fi
echo "PadHitTesting.swift: the same as RetroPlay's"

# RetroPlay's side: its two files in one module (its import of RetroPlayCore dropped, the core
# file being in the module), PadStick's two constants taken from PadControls.swift and
# PadTouchOutput from PadInputModel.swift, the driver
# appended to the touch file so it can reach the view's private methods
{ echo "import SwiftUI"; echo "enum PadStick {"; grep -E 'static let (touchT|t)ravelFraction' "$RP_CONTROLS"; echo "}"; } > "$WORK/PadStick.swift"
awk '/^struct PadTouchOutput/,/^}/' "$RP_MODEL" >> "$WORK/PadStick.swift"
grep -q touchTravelFraction "$WORK/PadStick.swift" && grep -q 'static let idle' "$WORK/PadStick.swift" || { echo "no PadStick.touchTravelFraction or PadTouchOutput in RetroPlay" >&2; exit 1; }
{ grep -v '^import RetroPlayCore' "$RP_TOUCH"; cat RetroPlayDriver.swift; } > "$WORK/PadTouchSurface.swift"
cp "$RP_CORE" "$WORK/RetroPlayPadHitTesting.swift"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET=arm64-apple-ios18.0-macabi
FLAGS=(-target "$TARGET" -sdk "$SDK" -swift-version 5 -O
       -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" -I "$SDK/System/iOSSupport/usr/lib/swift"
       -L "$SDK/System/iOSSupport/usr/lib/swift")
cd "$WORK"
xcrun swiftc "${FLAGS[@]}" -parse-as-library -emit-library -static -emit-module -module-name RP \
  RetroPlayPadHitTesting.swift PadStick.swift PadTouchSurface.swift
xcrun swiftc "${FLAGS[@]}" -parse-as-library -emit-library -static -emit-module -module-name AR \
  "$REPO/Artemis/Desktop/PadHitTesting.swift" "$REPO/Artemis/Desktop/PadTouch.swift" "$OLDPWD/ArtemisDriver.swift"
xcrun swiftc "${FLAGS[@]}" -I . -L . -lRP -lAR "$OLDPWD/main.swift" -o pad-parity
./pad-parity "$OUT"
