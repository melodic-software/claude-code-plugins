---
bump: minor
---

### Added

- `/session-flow:audit-sessions ticket --pattern '<regex>'`: groups stored sessions by the key the pattern matches in the title or branches, else the working directory. Per key it reports the sessions, output tokens, distinct linked PRs, gaps between sessions, and the first-to-last span, labeled a session-side proxy, not cycle time. `--branch` keeps the one key a branch name matches. The `sweep` report is unchanged.
- `/session-flow:retro session --pattern '<regex>'` adds a ticket section from that rollup when the current branch has a key.
