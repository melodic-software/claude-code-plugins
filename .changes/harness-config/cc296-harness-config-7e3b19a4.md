---
bump: minor
---

### Added

- **The settings audit flags model policy that is not in force.** Category H now reads `deniedModels` and `availableModelsMatch` and reports either one found in a user, project or local settings file as a warning, since we treat both as managed-only, and points at the settings reference for each key. The `availableModels` wildcard-mix row now says it assumes no managed `availableModelsMatch` or `deniedModels` applies, since this skill does not read managed settings.
- **The permission merge reports `!` carve-outs on their own.** A deny or ask `Read` or `Edit` rule whose pattern starts with `!` is now a `carveout` record naming the one settings file it came from, instead of being merged across scopes as if it reached every source. A carve-out whose pattern is a bare `!` is tagged `bare`, and its effect is reported as a known gap.

### Changed

- **The effort-pin baseline is refreshed against the current model-config page.** The page changed since the last baseline, but the effort levels it lists did not, so every pin still names a listed level.

### Fixed

- **The sandbox escape-surface table accounts for an admin-required sandbox.** The `excludedCommands` row and the strict-mode paragraph now tell the auditor to review loosening settings only in the scopes an admin-required sandbox still reads, and point at the sandboxing docs for which settings it ignores.
- **The automation-gaps audit no longer describes an old `/hooks` screen.** Its boundary note and its gotchas record now state our decision to leave hook enumeration to the native `/hooks` menu and point at the hooks docs for what the menu shows.
- **The C6-colonStar lint message describes what the rule matches.** A mid-pattern `:*` such as `Bash(git:* push)` matches commands with that literal colon (`git:<anything> push`), not nothing. The lint still fires on the same rules; only its message and criteria text changed.
