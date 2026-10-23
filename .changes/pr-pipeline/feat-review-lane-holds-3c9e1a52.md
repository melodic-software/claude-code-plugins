---
bump: minor
---

### Added

- Both review lanes hold a pull request for a person: `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/9aca743c4ed9aaf7870288a36586c3994e9321e4/.github/workflows/pr-review-cli.yml) v0.64.1 with `hold-label: needs-human`, and a changed file under `.github/standards/trusted-actors/**`, `.github/actions/check-trusted-trigger/**`, `**/CODEOWNERS` or `**/.gitmodules` holds as `trust-gate` whatever the review says ([Review-lane holds](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#review-lane-holds)).
- ci-status requires both review lanes on the head of a ready pull request: the newest `pull_request` run of each caller must have a successful status job whose `Apply the hold` step ran. A pending, failed, skipped or summary-mode review fails with the cause named; a lane the kill switch stopped passes; Dependabot, the release App and the standards-sync App are exempt by author id.
- ci-status fails when a review-lane hold was lifted by anyone but a person on the base's trusted-actor list: the first removal of the human-gated label after the newest hold comment or lane-added label event decides.
- `pr-feedback-dispatch.yml`'s `rerun-ci-status` job re-runs the head's ci-status job when either review lane completes on an open same-repository pull request, after polling at most 10 minutes for a ci-status already in progress.

### Changed

- `fix-ci` dispatch keys on the head's `ci-lanes` commit status instead of ci-status, so a hold, a pending review or a contract failure no longer summons it.
