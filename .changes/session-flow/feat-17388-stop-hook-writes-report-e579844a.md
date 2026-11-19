---
bump: minor
---

### Changed

- step-away: during an absence the Stop hook rewrites the away report's refused-actions and external-actions blocks itself, so the session no longer runs `away.py refresh` from a Bash command, which the Bash sandbox kept from writing the state. go-with-recommendations no longer runs `refresh` during an absence either.
- step-away: the watched-folder file scan runs only at `end` and on `refresh --files`; the first `refresh` after the report-by time no longer scans, so a report read before `end` has no files list yet.

### Security

- step-away: `away.py` refuses to rewrite the report when its folder resolves elsewhere than at `start` or the report is not a regular file, so a link planted by a sandboxed command cannot redirect the hook's write or copy a linked file into the report.
