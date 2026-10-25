# CI main gate bootstrap record (2026-10-25)

PR #23 switched iOS F0 main pushes to the blocking required tier and added
the separate `iOS Full Regression (Advisory)` workflow.

Because the gate change itself was structural, it could not pass the old
full gate: `select-test-scope.py` deliberately full-fallbacks on workflow,
script and governance changes. The owner approved a one-time bootstrap
merge. `enforce_admins` was temporarily disabled, the PR was merged, and
admin enforcement was immediately restored to `true`.

This is a CI-only bootstrap exception. It did not waive a product/test
assertion, change the 60/120s allowances, modify HomeLoadTests, or expand
DEC-016. The red full CI remains recorded on PR #23.

This docs-only follow-up is the first main push that runs the new required
tier (the PR itself is docs-only and may skip verification). Full regression
continues as a separate advisory workflow; its failure is visible but is not
part of `required-checks`.
