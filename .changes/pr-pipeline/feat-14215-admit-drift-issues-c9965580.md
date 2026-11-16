---
bump: minor
---

### Changed

- A trusted upstream-drift issue (github-actions[bot] wrote it, nobody else last edited it, and its title and first body line are the filer's) has one rule, `driftIssueId` in `admit.mjs`, read by the triage sweep, which now dispatches intake for it while still skipping every other github-actions[bot] issue, by admission criteria 7 and 9, by the issue lane's `issue.json`, and by pr-verify. Its spec is one fixed template (`driftSpecText`) built from the upstream id, with done-when items and the design-change stop, never from its body; pr-verify's drift spec gains those lines. `apply-verdict.mjs` and `check-blockers.mjs` do not read the rule yet, so they still turn such an issue away.
