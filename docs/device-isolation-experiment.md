# Device isolation experiment

## Question

Does moving the formal execution to a separate fresh Simulator from the
enumerator change the runner/launch behavior? This is a mechanism check,
not a claim that a new device eliminates `FBSOpenApplication...Busy`.

## Design

- One build; enumeration runs on a fresh `MallEnum-*` device.
- The enumeration device is deleted before the execution job starts.
- Each execution cycle creates a new `MallExec-*` device; no manual
  runner preinstall, no automatic retry, exact 143 expected methods,
  original assertions and 60/120 limits.
- Timeline records device creation, boot, app list, test start/end and
  result validation.
- On failure, `simctl diagnose` runs before the execution device is
  deleted.
- Cleanup is per cycle, after test/diagnostics; no setup-step `trap`
  deletes a device before the test starts.
- `repetitions` is 1..20. The observation window retains every success
  and failure; failures are not cleared to manufacture a streak.

## Not done

- No runner preinstall gate (Apple's listapps semantics are not assumed).
- No setup retry in this experiment.
- No required/CI policy change.
