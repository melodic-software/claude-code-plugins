---
bump: minor
---

### Added

- The merge gate reads a pull request that closes no issue as linked to the one issue its body names with a plain `Refs: #<n>` line (owner decision 2026-10-23), in the pr-merge lane and the worker tier alike: the work class, its label provenance, the lane claim, the cost decision, the verifier-verdict binding and the enqueue recheck read that issue as they read a closing issue. A closing issue always wins. A `Refs:` line inside an HTML comment or a fenced code block, or not in the first column, names nothing; one in any other form refuses `refs-line-not-plain`, two or more issues refuse `refs-issues:<n>`, and a pull request number refuses `refs-not-an-issue`. An adopted pull request whose `Refs:` lines name no single issue stays its own intent, as before. Nothing closes the `Refs:` issue on merge. The gate allows a verifier pass only when the verdict's `spec_kind` matches how the issue is linked now, so a pass judged as a `Refs:` slice never covers the same issue closed, nor the reverse (`verify:spec-changed`). The cross-pull-request repeated-fail cap also counts each `fail` of a pull request the issue's timeline shows referencing it whose verdict records the issue, so closing a failed pull request and opening a new `Refs:` one does not reset the count.
