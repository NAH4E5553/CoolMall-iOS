#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SIM="${MALL_SIMULATOR_ID:?missing simulator}"
BASE="${MALL_DIFF_BASE:?missing base}"
HEAD="${MALL_DIFF_HEAD:?missing head}"
RUN="${MALL_EXPERIMENT_RUN:-.build/isolation-experiment}"
rm -rf "$RUN"
mkdir -p "$RUN"
xcodebuild build-for-testing \
  -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -testPlan CoolMalliOS \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$RUN/DerivedData" CODE_SIGNING_ALLOWED=NO \
  > "$RUN/build-for-testing.log" 2>&1
xcodebuild test -collect-test-diagnostics never -enumerate-tests \
  -test-enumeration-style flat -test-enumeration-format json \
  -test-enumeration-output-path "$RUN/test-enumeration.json" \
  -project CoolMalliOS.xcodeproj -scheme CoolMalliOS -testPlan CoolMalliOS \
  -configuration Debug -parallel-testing-enabled NO \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$RUN/DerivedData" CODE_SIGNING_ALLOWED=NO \
  > "$RUN/enumerate.log" 2>&1
GITHUB_EVENT_NAME=push MALL_VERIFICATION_TIER=required \
  MALL_DIFF_BASE="$BASE" MALL_DIFF_HEAD="$HEAD" \
  python3 Scripts/select-test-scope.py plan "$RUN/test-scope.json"
python3 Scripts/select-test-scope.py resolve "$RUN/test-scope.json" \
  "$RUN/test-enumeration.json" "$RUN/expected-tests.txt"
python3 Scripts/select-test-scope.py check-source "$RUN/test-scope.json" "$RUN/expected-tests.txt"
python3 Scripts/check-test-support-scope.py --scope "$RUN/test-scope.json" \
  --enumeration "$RUN/test-enumeration.json" --tier required
python3 Scripts/split-test-shards.py --expected "$RUN/expected-tests.txt" --out-dir "$RUN/shards"
python3 - "$RUN" <<'PY'
import copy, json, sys
from pathlib import Path
run = Path(sys.argv[1])
parent = json.loads((run / 'test-scope.json').read_text())
for name in ('all', 'ui', 'nonui'):
    methods = (run / 'shards' / f'expected-{name}.txt').read_text().splitlines()
    scope = copy.deepcopy(parent)
    scope['mode'] = 'selected'
    scope['reason'] = 'isolation-experiment-shard'
    scope['expected'] = methods
    # check-test-results validates discovery targets against the full
    # enumeration; only expected is sharded. Keep the parent discovered list.
    scope['discovered'] = parent['discovered']
    (run / 'shards' / f'scope-{name}.json').write_text(json.dumps(scope, indent=2) + '\n')
PY
find "$RUN" -maxdepth 4 -name '*.xctestrun' -print
find "$RUN" -type f -name 'expected-*.txt' -o -name 'scope-*.json' | sort
