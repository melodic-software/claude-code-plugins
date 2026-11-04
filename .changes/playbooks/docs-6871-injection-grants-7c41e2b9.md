---
bump: patch
---

### Changed

- `skill-authoring`: the skill criteria state the grant rule for injected commands (a narrow `allowed-tools` grant covering each subcommand on the line, in the rule form of the tool that runs it, or a move to a body instruction), and the `shell:` guidance says to grant a `shell: powershell` injection with a `PowerShell(...)` rule, not a `Bash(...)` rule.
