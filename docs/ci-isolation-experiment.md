# CI isolation experiment (A/B)

Status: design + shard tooling; not run.

## Fixed conditions

- Same commit, same `build-for-testing` artifact, same real 152 parent inventory.
- Same Xcode/runtime, simulator preparation, original assertions/60/120 limits.
- Both groups use `MALL_TEST_DIAGNOSTICS=on-failure`; record image version and actual test order.
- One A/B pair first; old `never` runs are historical reference.

## Groups

- A: one job, full 152.
- B: non-UI 135 and UI 17 in separate jobs, each on a clean simulator.
- Build once; upload `.xctestrun` + `Build/Products` + checksums; A/B download and verify.
- Use `xcodebuild test-without-building -xctestrun` for both.

## Shards

Use `Scripts/split-test-shards.py --expected expected.txt --out-dir shards`:

- `expected-all.txt` = immutable parent 152
- `expected-ui.txt` = 17
- `expected-nonui.txt` = 135
- disjoint, union equals parent; duplicate/empty fails.

## Result validation

- Keep each shard's raw exit code, logs, xcresult, banner audit.
- Verify each shard's actual executed set by exact method ID.
- A and B produce separate verdicts; never combine passing subsets into a false 152 green.
- Missing/skipped/cancelled/deferred are reported, not counted as pass.

## Decision

| A | B | Meaning |
| --- | --- | --- |
| red | green | Supports isolation hypothesis only; host root cause not proven |
| green | green | No repro in this run; not proof of fix |
| green | red | Isolation made it worse; inspect shard/order/environment |
| red | red | Isolation does not explain; investigate App/XCTest/query/environment |

No merge based on this experiment; PR29 stays draft.
