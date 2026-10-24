---
bump: minor
---

### Changed

- Intake no longer gates on work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): a triage verdict proposing no class, a class outside the repository's labels, `work-class: structural`, or a class a person set reaches `status: ready` on its Size, Complexity, Uncertainty and flags alone, and admission and the work-unblock mark no longer refuse by class. `work-class: untrusted-provenance` still holds the issue and refuses admission (`.github/scripts/intake-triage/apply-verdict.mjs`, `admit.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`).
