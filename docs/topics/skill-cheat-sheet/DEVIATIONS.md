# Deviations from the approved plan

Logged at deviation time per the orchestrated-execution discipline; pruned with the contract
slice in Phase 6 after being carried into the PR description.

## 1. Portability-token migration folded into Phase 4 (2026-07-27)

- **Planned:** Phase 4 touches check-skill.sh only to add the summary-cap check.
- **Found:** both checker files carry 8 pre-existing `\S`/`\b`/`\<` regex tokens that
  `scripts/check-shell-portability.sh` rejects; the gate is changed-file scoped, so touching the
  files in this branch newly exposes them to the CI portability lane at PR time.
- **Done instead:** a second, separate commit in Phase 4 migrates all 8 sites to
  semantics-preserving POSIX forms, each probed before/after. No suppressions.
- **Why this option:** suppression annotations require end-user approval (engineering-quality
  rule); deferring to Phase 5 would land a red draft PR; migration is the root-cause fix with
  the smallest blast radius (two files already in the changed set).
- **Blast radius:** check semantics unchanged (probed per site; full checker test suite green).

## 3. Metadata keys renamed: cheatsheet-* → workflow-stage / summary / cadence (2026-07-27)

- **Planned:** PLAN resolution 1 named the keys `cheatsheet-stage` / `cheatsheet-summary` /
  `cheatsheet-cadence` (consumer-prefixed per the `discipline-*` precedent).
- **Changed:** user decision mid-implementation (logged on #1227,
  issuecomment-5086823909) — keys describe general skill classification, not the consumer.
  New names: `workflow-stage`, `summary`, `cadence`. Enum values unchanged. Scope keys only:
  the sheet doc and generator/config script names keep "cheatsheet".
- **Execution:** one scripted rename sweep (config, generator, tests, skill-quality summary-cap
  check, idempotent re-sweep of the 121 skills, regenerated sheet), independently verified,
  before the draft PR opens. PLAN.md prose referencing `cheatsheet-*` keys is superseded by
  this entry + the #1227 comment rather than rewritten line-by-line.

## 2. ci.yml step for the generator test added to Phase 5 (2026-07-27)

- **Planned:** Phase 5 CI wiring listed validate-plugins.sh, docs-only-paths.txt, and
  check-docs-only.test.sh only.
- **Found (Phase 2 code-design review):** `run-plugin-tests.sh` discovers only
  `plugins/**/*.test.sh`; every `scripts/*.test.sh` needs an explicit ci.yml step, so the
  committed generator test would never run in CI.
- **Done instead:** PLAN.md Phase 5 amended (commit `8c75d64b`) to add the
  `bash scripts/generate-cheatsheet.test.sh` step.
