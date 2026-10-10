---
bump: minor
---

### Added

- **The settings audit flags model policy that is not in force.** Category H now reads `deniedModels` and `availableModelsMatch` and reports either one found in a user, project or local settings file as a warning: Claude Code reads both only from managed settings, so the policy its author wrote does not apply. The `availableModels` wildcard-mix row now says it assumes the default match mode, because a managed `availableModelsMatch` can change how entries match.
- **The permission merge reports `!` carve-outs on their own.** A deny or ask `Read` or `Edit` rule whose pattern starts with `!` is now a `carveout` record naming the one settings file it came from, instead of being merged across scopes as if it reached every source. A carve-out whose pattern is a bare `!` is tagged `bare`, and its effect is reported as a known gap.

### Fixed

- **The sandbox escape-surface table matches what an admin-required sandbox ignores.** The `excludedCommands` row and the strict-mode paragraph now say that the repository's own project and local entries are ignored when the sandbox is admin-required, while user settings and `--settings` can still add entries, and point at the sandboxing docs for the full list of ignored settings.
- **The automation-gaps audit no longer describes an old `/hooks` screen.** Its boundary note and its gotchas record now state our decision to leave hook enumeration to the native `/hooks` menu and point at the hooks docs for what the menu shows.
- **The C6-colonStar lint message describes what the rule matches.** A mid-pattern `:*` such as `Bash(git:* push)` matches commands with that literal colon (`git:<anything> push`), not nothing, and Claude Code now warns about it at startup. The lint still fires on the same rules; only its message and criteria text changed.
