---
bump: patch
---

### Fixed

- The shared hook library's command reader now says, when shfmt rejects text a guard lifted out of the command and named with `HOOK_BPS_SPAN`, which guard refused, that shfmt's `line:col` counts from the start of that text rather than the command, and the text's first 60 characters. Its own second readings (a backtick's unescaped text, a joined here-doc body) name themselves the same way. A refusal of the command itself reads as before.
