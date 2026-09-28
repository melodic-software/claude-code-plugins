# Guardrails Windows Git Bash suite gap

## Decision

**Do not add the six failing guardrails suites to the informational Windows CI
lane.** Keep `test-windows.yml` small; Linux remains the required runner for
those suites. Overlap with #3683 is recorded, not duplicated here.

- **Option A (taken):** host-skip / CI-note. The Windows lane stays the named
  five suites plus the later named extras already in the workflow. The six
  guardrails failures from #4527 stay off that job until a Windows Git Bash
  host shows they pass, or a host-skip rewrite lands.
- **Option B (declined):** add the six suites to `.github/workflows/test-windows.yml`
  now. That would paint the informational lane red on every run, or skip-green
  without a host probe.

**Claim:** Windows CI does not run guardrails' 22 hook suites; the six
Git-Bash-host failures are not a merge-gate gap.
**Basis:** #4527 (16 pass / 6 fail on Windows 11 Git Bash 5.3.15 at
`origin/main` 63ed8aad9, 2026-09-26). `.github/workflows/test-windows.yml`
names its Windows job and says adding a platform-agnostic suite buys no
coverage. #3683 (open PR) covers `hardcoded-path-check` host-skip and leaves
`block-windows-drive-tmp` as a real MSYS writer-path gap. The four suites
#3683 does not name are `block-hook-bypass`, `coverage-manifest`,
`run-guards`, and `secret-pattern-detection`.
**As of:** 2026-09-28.
**Recheck:** a Windows Git Bash host where the four extra suites pass, or
#3683's drive-tmp fix lands and someone re-runs the six.

## Rationale

- The Windows job is informational and is kept small on purpose (process
  creation cost; required lanes already run the same bash string logic on
  Linux).
- Two of the six overlap #3683. Closing this issue in favor of #3683 for
  those two is correct; this record keeps the four extra names and the CI
  ask so they are not lost.
- Adding failing suites to CI without a host rewrite would only fail-open or
  fail-noise.

## Revisit when

- A Windows Git Bash host re-runs `plugins/guardrails/hooks/*.test.sh` and
  `plugins/guardrails/lib/git-hooks/*.test.sh` and the four extra suites pass,
  or
- #3683 merges a drive-tmp fix and the remaining four get a host-skip or a
  real fix.

## Prior requests

- #4527 (2026-09-28): needs-triage Windows CI gap; Option A recorded here.
- #3683: overlapping `hardcoded-path-check` and `block-windows-drive-tmp`.
