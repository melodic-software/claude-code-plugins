---
bump: minor
---

### Added

- `bug_path.mode` in `docs/conventions/work-items.yaml` sets how far `/work-items:work` runs a bug item. `full`, the default, runs the whole bug path through a fix and a draft pull request. `investigate` stops after the root cause: the run creates no branch, writes no fix and opens no pull request. It posts one comment on the item whose first line is `<!-- work-items:investigation outcome=<outcome> -->`, then releases the claim and clears the session's own assignee. CI mode (`--issue <n> --ci`) does not read the key. The comment carries the outcome (`cause-named`, `causes-ranked` or `not-reproduced`), the reproduction evidence, the ranked causes and the access the diagnosis could not reach. A new eval case, `wk-bug-investigate-mode-marker-only`, covers it.
