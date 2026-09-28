# Node and Pester CI runners outside the four sub-projects

Recorded park for
[#3703](https://github.com/melodic-software/claude-code-plugins/issues/3703).
`ci.yml` has no runner for Node suites outside four sub-projects, or for
Pester, on either the pull-request path or the push path.

## Decision

**Park unpaid runner expansion.** Keep the warn-and-count contract. Do not
add a Node runner or a Pester lane until a maintainer funds it.

- **Option A (taken):** record each remaining exclusion with a reason that
  outlives this issue. The contract-suite step still warns and counts. It
  does not fail the pull request for a gap the push path shares.
- **Option B (declined):** build a Node runner that respects each package's
  own test command (and skips the testing-audit eval fixtures) plus a Pester
  lane on `test-windows`.

**Claim:** twelve Node suites outside miro, ai-briefing generate,
video-digest extraction, and course-digest extraction have no CI runner on
either path. Pester under `machine-health` Windows tests and
`kindle-dedrm` manage tests has no lane. Warn-and-count stays.
**Basis:** `.github/workflows/ci.yml` still emits
`::warning::No step in this workflow executes these selected suites (#3703)`
and names the hole in the contract-suite `status=3` branch.
`scripts/affected-tests.sh --run` is shell-only (exit 3 for other
ecosystems). `scripts/run-plugin-tests.sh` discovers `plugins/**/*.test.sh`
only. #3773 sharded `test-linux` and did not add these runners. Counted
2026-09-28 on `origin/main`: 12 Node files outside the four sub-projects
(6 real suites including `plugins/attribution/skills/audit/scripts/fingerprint.test.mjs`,
plus 6 `plugins/testing/skills/audit/evals/fixtures/**` files that must not
run as suites).
**As of:** 2026-09-28.
**Recheck:** a maintainer funds a Node runner that uses each package's own
test command and excludes the testing-audit fixture corpus, and/or a Pester
lane on `test-windows`.

## Rationale

- A blanket `node --test` sweep would execute the testing-audit eval
  fixtures, which are deliberately vacuous or can't-fail corpora.
- Guessing a runner from a path is worse than declining: the wrong runner
  either errors as if the suite failed or exits 0 having run nothing.
- Failing the PR step would red contributors for a repository-wide hole the
  push path shares.

## Revisit when

- a maintainer names the Node invocation per remaining real suite and adds
  steps, or
- `test-windows.yml` grows a Pester job for the two Windows-only trees.

## Prior requests

- #3703 (2026-09-28): needs-human; Option A recorded here.
- #3773: sharding; did not close this coverage hole.
