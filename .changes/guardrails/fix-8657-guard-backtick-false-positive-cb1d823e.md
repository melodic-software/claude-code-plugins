---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer refuses a read-only command that names "PR Merge" in prose beside a backtick (#8657).** The backtick refusal matched `pr merge` anywhere in the text, so a `jq` filter testing for "Gated PR Merge" next to a backtick in a `grep` pattern, or a heredoc `gh issue comment --body-file -` body that named the guard and used a backtick, was refused as a merge. A `pr merge` now counts only when the word before `pr` is `gh` once quotes and backslashes are dropped (`gh`, `/usr/bin/gh`, `gh.exe`, `g""h`), or holds a `$` or backtick so the command word cannot be read (`$GH`, `gh${IFS}pr`); those still fail closed. Words bash drops before argv are stepped over first, so empty quotes or a backslash glued to `pr` (`gh ''pr`, `gh \pr`) and a redirection between `gh` and `pr` (`gh 2>&1 pr`, `gh > /dev/null pr`, `gh</dev/null pr`) still read as gh. The REST merge route and GraphQL mutation names still refuse wherever they appear.
