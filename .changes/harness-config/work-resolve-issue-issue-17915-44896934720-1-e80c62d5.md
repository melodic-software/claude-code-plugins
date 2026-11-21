---
bump: patch
---

### Fixed

- The audit's `failIfUnavailable` row in `required-permissions.md` now says that, from Claude Code
  2.1.328, a sandbox that cannot start refuses the next sandboxed Bash command with a message that
  the sandbox is off for the session. Before, the row said commands run unsandboxed after a
  warning. A boundary still needs `failIfUnavailable: true` (#17915).
