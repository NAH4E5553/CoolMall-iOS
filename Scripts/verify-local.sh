#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MALL_SIMULATOR_ID:?Set MALL_SIMULATOR_ID to an available iOS Simulator UDID}"
MALL_RUN=".build/verification/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$MALL_RUN"
exec > >(tee "$MALL_RUN/run.log") 2>&1
# The trace records exact commands. pipefail and ERR preserve failures, never a false green.
trap 'code=$?; echo "FAIL: exit=$code; artifacts=$MALL_RUN"; exit "$code"' ERR
set -x
if git rev-parse --verify HEAD >/dev/null 2>&1; then git rev-parse HEAD; git status --short; else echo 'No commit SHA (initial working tree)'; fi
Scripts/check-toolchain.sh
xcrun simctl list runtimes
xcrun simctl list devices available
Scripts/check-format.sh
Scripts/check-boundary-negative.sh
for MALL_CONFIGURATION in Debug Release; do
    xcodebuild build -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -configuration "$MALL_CONFIGURATION" -destination 'generic/platform=iOS Simulator' -derivedDataPath "$MALL_RUN/DerivedData" CODE_SIGNING_ALLOWED=NO > "$MALL_RUN/$MALL_CONFIGURATION.log" 2>&1
done
# Prepare one simulator before timed UI interaction; Swift Testing's task-based races remain tested.
xcrun simctl bootstatus "$MALL_SIMULATOR_ID" -b
MALL_APP="$MALL_RUN/DerivedData/Build/Products/Debug-iphonesimulator/CoolMalliOS.app"
MALL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$MALL_APP/Info.plist")
xcrun simctl install "$MALL_SIMULATOR_ID" "$MALL_APP"
xcrun simctl launch --terminate-running-process "$MALL_SIMULATOR_ID" "$MALL_BUNDLE_ID"
xcrun simctl terminate "$MALL_SIMULATOR_ID" "$MALL_BUNDLE_ID"
xcodebuild test -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -testPlan CoolMalliOS -configuration Debug -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$MALL_SIMULATOR_ID" -derivedDataPath "$MALL_RUN/DerivedData" -resultBundlePath "$MALL_RUN/Tests.xcresult" CODE_SIGNING_ALLOWED=NO > "$MALL_RUN/tests.log" 2>&1
python3 Scripts/check-test-results.py "$MALL_RUN/Tests.xcresult"
echo "PASS: local F0 gates; artifacts=$MALL_RUN; remote CI and minimum-runtime coverage are separate."
