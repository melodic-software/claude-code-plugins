---
bump: patch
---

### Fixed

- **`tidy`: the open-PR pre-computed row no longer aborts the skill outside auto mode.** It piped
  into a brace group holding quotes (`| { grep -E '^(Open tidy|Throttle)' || echo "unknown"; }; :`),
  which Claude Code's shell permission check refuses. The row is now
  `open-pr-count.sh 2>/dev/null | grep -E '^(Open tidy|Throttle)' || echo unknown`. Injections ran
  without `pipefail` in a Claude Code 2.1.296 probe, where it renders as before; under `pipefail` a
  failed count can add one redundant `unknown` line after the script's own `unknown` lines.
