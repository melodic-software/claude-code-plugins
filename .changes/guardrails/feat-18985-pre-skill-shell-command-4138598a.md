---
bump: minor
---

### Added

- The Bash and PowerShell guards now also check each command a skill injects as it loads
  (`` !`...` `` and ` ```! ` blocks), through a `PreSkillShellCommand` hook entry that runs the
  same guards, arguments, timeout and `onFailure: "block"` as the `PreToolUse` `Bash|PowerShell`
  entry. A command a guard refuses on a tool call is not run while the skill loads, and the skill
  loads without its output. The entry requires Claude Code 2.1.332 or later; an earlier version
  runs injected commands without calling it.

### Changed

- The guard dispatcher no longer reads `hook_event_name` from the payload. Its telemetry and
  abort-notice event label is always `PreToolUse`, the reply shape the hooks reference asks of a
  script shared with `PreSkillShellCommand`, and no guard's verdict depends on which event fired.
