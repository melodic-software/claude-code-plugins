# Gitleaks all-refs scan on pull requests

Recorded park for
[#3599](https://github.com/melodic-software/claude-code-plugins/issues/3599).
`scan-mode: git` walks every ref in the clone, so one false positive on any
in-flight branch turns the `hygiene` gitleaks step red on every other PR.

## Decision

**Keep the current scan default. Do not change the ci-workflows gitleaks
contract until that work is funded.** False positives stay on
`.gitleaksignore` or an inline `gitleaks:allow` comment, which is this
repository's own policy in `.gitleaks.toml`.

- **Option A (taken):** document the known posture. Leave
  `.github/workflows/ci.yml` on `scan-mode: git`. Park scoping the PR path to
  the range under review (`--log-opts` over the PR's own commits, full-history
  kept on the main-branch push run).
- **Option B (declined):** change the shared gitleaks action's inputs or
  contract from this checkout so a PR is judged only on its own commits.

**Claim:** hygiene gitleaks keeps `scan-mode: git` over all fetched refs. A
finding on any reachable branch can fail every other PR. The scan-default
change is parked.
**Basis:** #3599 (reproduced against gitleaks 8.30.1: all-refs scan finds a
leak the PR-only clone does not). `.github/workflows/ci.yml` still pins
`melodic-software/ci-workflows/.github/actions/gitleaks@4610c31e92eb1c4b24981e2f200ac87bdb2a1753`
(v0.27.1) with `scan-mode: git` and `fetch-depth: 0` on checkout. An inline
`gitleaks:allow` does not clear a finding already in history under `git`
mode; `.gitleaksignore` does, because gitleaks reads it from the checked-out
tree. #3618 landed that ignore file; this issue's remaining load-bearing item
is the scoping change.
**As of:** 2026-09-28.
**Recheck:** the ci-workflows gitleaks action grows a documented PR-range /
`log-opts` input, this repository's hygiene step passes it, and a maintainer
funds the contract change.

## Rationale

- Scoping is a shared-action contract, not a one-line caller edit.
- Annotating or ignoring one fingerprint does not terminate the blast radius:
  the next false positive on any in-flight branch fails every PR again.
- The current ignore file is the unblocking mechanism named by
  `.gitleaks.toml`. Empty fingerprints today mean the original pair is no
  longer reachable, not that the scan default changed.

## Revisit when

- ci-workflows publishes a PR-range scan input this caller can pass, or
- a maintainer funds rewriting the hygiene gitleaks step to supply
  `--log-opts` over the pull request's own commits.

## Prior requests

- #3599 (2026-09-28): needs-human; Option A recorded here.
- #3610: duplicate of #3599; acceptance criteria carried there.
- #3618: `.gitleaksignore` unblocks PRs; does not close the scan-default item.
