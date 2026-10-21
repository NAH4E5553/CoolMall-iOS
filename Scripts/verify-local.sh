#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
MALL_RUN=".build/verification/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$MALL_RUN"
# The logger must survive INT/TERM long enough to retain EXIT-trap output.
# It exits on EOF once this shell and its command close the pipe.
exec > >(trap '' INT TERM; tee "$MALL_RUN/run.log") 2>&1
# Keep the verification exit code even if recording fails. Recording failure
# after otherwise successful verification is itself a failure, never a green.
MALL_OUTCOME=failed
MALL_TIMINGS="$MALL_RUN/stage-timings.json"
finish_run() {
    local code=$? recording=0
    trap - EXIT INT TERM
    set +e
    python3 Scripts/verification-timing.py finalize "$MALL_TIMINGS" "$code" "$MALL_OUTCOME" || recording=$?
    python3 Scripts/verification-timing.py report "$MALL_TIMINGS" > "$MALL_RUN/stage-timings.md" || recording=$?
    if [ "$recording" -ne 0 ]; then
        echo "FAIL: timing recording exit=$recording; verification exit=$code"
        if [ "$code" -eq 0 ]; then code=65; fi
        # A readable ledger distinguishes gate success from entry/report failure.
        # If the ledger itself is broken, stderr and the nonzero exit remain authoritative.
        python3 Scripts/verification-timing.py recording-failed "$MALL_TIMINGS" "$code" || :
    fi
    if [ "$code" -eq 0 ]; then
        echo "PASS: local F0 gates; artifacts=$MALL_RUN; remote CI and minimum-runtime coverage are separate."
    else
        echo "FAIL: exit=$code; artifacts=$MALL_RUN"
    fi
    exit "$code"
}
trap finish_run EXIT
trap 'MALL_OUTCOME=cancelled; exit 130' INT
trap 'MALL_OUTCOME=cancelled; exit 143' TERM
stage_start() { python3 Scripts/verification-timing.py start "$MALL_TIMINGS" "$1"; }
stage_end() { python3 Scripts/verification-timing.py end "$MALL_TIMINGS"; }
python3 Scripts/verification-timing.py init "$MALL_TIMINGS"
set -x
stage_start configuration
if [ -z "${MALL_SIMULATOR_ID-}" ]; then
    echo 'Set MALL_SIMULATOR_ID to an available iOS Simulator UDID'
    exit 1
fi
MALL_TEST_DIAGNOSTICS="${MALL_TEST_DIAGNOSTICS-never}"
case "$MALL_TEST_DIAGNOSTICS" in
    never|on-failure) ;;
    *) echo 'MALL_TEST_DIAGNOSTICS must be never or on-failure'; exit 64 ;;
esac
python3 Scripts/select-test-scope.py plan "$MALL_RUN/test-scope.json"
stage_end
stage_start environment
if git rev-parse --verify HEAD >/dev/null 2>&1; then git rev-parse HEAD; git status --short; else echo 'No commit SHA (initial working tree)'; fi
Scripts/check-toolchain.sh
xcrun simctl list runtimes
xcrun simctl list devices available
stage_end
stage_start format
Scripts/check-format.sh
stage_end
stage_start policy-negative
Scripts/check-boundary-negative.sh
stage_end
for MALL_CONFIGURATION in Debug Release; do
    stage_start "build-$MALL_CONFIGURATION"
    xcodebuild build -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -configuration "$MALL_CONFIGURATION" -destination 'generic/platform=iOS Simulator' -derivedDataPath "$MALL_RUN/DerivedData" CODE_SIGNING_ALLOWED=NO > "$MALL_RUN/$MALL_CONFIGURATION.log" 2>&1
    stage_end
done
# Prepare one simulator before timed UI interaction; Swift Testing's task-based races remain tested.
stage_start simulator-prepare
xcrun simctl bootstatus "$MALL_SIMULATOR_ID" -b
MALL_APP="$MALL_RUN/DerivedData/Build/Products/Debug-iphonesimulator/CoolMalliOS.app"
MALL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$MALL_APP/Info.plist")
xcrun simctl install "$MALL_SIMULATOR_ID" "$MALL_APP"
xcrun simctl launch --terminate-running-process "$MALL_SIMULATOR_ID" "$MALL_BUNDLE_ID"
xcrun simctl terminate "$MALL_SIMULATOR_ID" "$MALL_BUNDLE_ID"
stage_end
stage_start test-build-discovery
xcodebuild test -collect-test-diagnostics "$MALL_TEST_DIAGNOSTICS" -enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path "$MALL_RUN/test-enumeration.json" -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -testPlan CoolMalliOS -configuration Debug -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$MALL_SIMULATOR_ID" -derivedDataPath "$MALL_RUN/DerivedData" CODE_SIGNING_ALLOWED=NO > "$MALL_RUN/test-discovery.log" 2>&1
python3 Scripts/select-test-scope.py resolve "$MALL_RUN/test-scope.json" "$MALL_RUN/test-enumeration.json" "$MALL_RUN/expected-tests.txt"
python3 Scripts/select-test-scope.py check-source "$MALL_RUN/test-scope.json" "$MALL_RUN/expected-tests.txt"
stage_end
# Full inventories also use explicit methods, so execution cannot silently drift.
stage_start test-execute-diagnostics
xcodebuild test-without-building -only-testing "@$MALL_RUN/expected-tests.txt" -collect-test-diagnostics "$MALL_TEST_DIAGNOSTICS" -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -testPlan CoolMalliOS -configuration Debug -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$MALL_SIMULATOR_ID" -derivedDataPath "$MALL_RUN/DerivedData" -resultBundlePath "$MALL_RUN/Tests.xcresult" CODE_SIGNING_ALLOWED=NO > "$MALL_RUN/tests.log" 2>&1
stage_end
stage_start test-result-validation
python3 Scripts/check-test-results.py "$MALL_RUN/Tests.xcresult" --scope "$MALL_RUN/test-scope.json"
python3 Scripts/select-test-scope.py check-source "$MALL_RUN/test-scope.json" "$MALL_RUN/expected-tests.txt"
stage_end
