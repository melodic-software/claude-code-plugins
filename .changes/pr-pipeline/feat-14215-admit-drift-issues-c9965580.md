---
bump: minor
---

### Changed

- A trusted upstream-drift issue (github-actions[bot] wrote it, nobody else last edited it, and its title and first body line are the filer's) reaches the issue lane with no owner step. One rule in `admit.mjs` (`driftIssueId`, through `authorTrust` for a REST read) decides it at every author gate: the triage sweep, which now dispatches intake for it while still skipping every other github-actions[bot] issue; `apply-verdict.mjs`; admission criteria 7 and 9; `check-blockers.mjs`; and `write-issue.mjs`. pr-verify reads the same rule. Its spec is one fixed template (`driftSpecText`) built from the upstream id, with done-when items and the design-change stop, never from its body; pr-verify's drift spec gains those lines. Such an issue is never split: admission takes it at any Size and the lane runs it at `split-child-size`. The filer's own body rewrite after admission no longer stops the lane run.
