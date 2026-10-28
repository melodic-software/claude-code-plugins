---
bump: minor
---

### Added

- `/source-control:pull-request create` writes a `## Remaining` section when the body links an issue with `Refs:` and closes nothing. It lists what stays open on that issue: its unchecked acceptance items, its open sub-issues, or the slices its body lists, as plain bullets without what this PR delivers. An issue with none gets one line naming what this PR delivers and what closes the issue, with no closing keyword before the issue number. pr-verify fails a `Refs:` pull request whose body names no remaining work, so a body drafted by create now passes that rule without a manual edit.
