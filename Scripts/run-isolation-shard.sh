#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SIM="${MALL_SIMULATOR_ID:?missing simulator}"
SHARD="${1:?missing shard}"
OUT="${2:?missing output}"
XCTEST="${3:?missing xctestrun}"
TRACE="${4:-0}"
mkdir -p "$OUT"
CMD=(xcodebuild test-without-building -xctestrun "$XCTEST" \
  -destination "platform=iOS Simulator,id=$SIM" \
  -only-testing "@$SHARD" -parallel-testing-enabled NO \
  -resultBundlePath "$OUT/Tests.xcresult" \
  -collect-test-diagnostics on-failure CODE_SIGNING_ALLOWED=NO)
if [ "$TRACE" = "1" ]; then
  python3 Scripts/with-banner-trace.py "$SIM" "$OUT/banner-trace.log" -- "${CMD[@]}" > "$OUT/tests.log" 2>&1
else
  "${CMD[@]}" > "$OUT/tests.log" 2>&1
fi
CODE=$?
echo "$CODE" > "$OUT/exit.txt"
if [ ! -f "$OUT/banner-trace.status.log" ]; then
  printf '{"commandExitCode": %s, "exitCode": %s}\n' "$CODE" "$CODE" > "$OUT/banner-trace.status.log"
fi
exit 0
