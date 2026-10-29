---
bump: minor
---

### Added

- `block-cross-domain` now denies a Bash or PowerShell command, from a session whose directory is in one identity domain, that names a path of another domain: one of its roots, or `~/src/github.com/<owner>` or `~/worktrees/github.com/<owner>` for an owner the map lists under it. A read is denied as well as a write. The guard matches a path in any case and spelled as a Windows drive path with either slash or escaped backslashes, in its MSYS, Cygwin and WSL drive forms, or below `HOME` after `~`, `$HOME` or `%USERPROFILE%` ([#9744](https://github.com/melodic-software/claude-code-plugins/issues/9744)). The decision is a PreToolUse `deny` on stdout whose reason names the session's domain and the others, and the exit stays 0. A marker alone never denies, and from a session outside every domain's paths nothing is denied. With no map the guard still does nothing, and `block_cross_domain_enabled` turns it off.

### Changed

- `block-cross-domain` classifies the session directory by an owner's `~/src/github.com/<owner>` and `~/worktrees/github.com/<owner>` directories as well as by roots, the longest path winning, so a session inside an owner's clone is in that owner's domain. It also drops quotes from the command text before its prefilter, so `"$HOME"/<path>` is parsed like `$HOME/<path>`. The compiled cache now changes with `HOME` as well as with the map.
