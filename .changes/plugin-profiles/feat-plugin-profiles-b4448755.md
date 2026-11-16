---
bump: minor
---

### Added

- The `plugin-profiles` plugin, on by default: named profiles of plugins to switch on, one YAML file each, shipped in `profiles/`, per user in `~/.claude/plugin-profiles/` and per repository in `docs/conventions/plugin-profiles/`; a same-named file at a higher level extends the one below with `plugins` and `remove` lines. Ships seven profiles: `always-on`, `discovery`, `planning`, `interface-design`, `build`, `review` and `harness-upkeep`, each with a description line saying when to pick it.
- `scripts/profiles.mjs apply <name> --for folder|initial|session` previews the plugins it switches on and off, pinned and missing plugins with their install commands, and the plugins of other marketplaces it leaves alone, then writes only the `enabledPlugins` and `skillOverrides` entries of `.claude/settings.local.json`, user `settings.json` or a one-session `--settings` file, all or nothing, on `--yes` or a yes at the prompt. A plugin it switches on with a missing required prerequisite is named with the tool, its install line and the consequence, and `--yes` alone does not apply it.
- `status` names the recorded profile, each entry that differs, plugins installed since and an unfinished switch; `clear` restores every entry to its value before the first apply and removes a settings file the tool created; `inventory` lists installed plugins with their dependencies and what each ships.
- `check` fails when a shipped profile names a plugin missing from the catalog, uses another marketplace than the catalog's name (naming the fix), lacks a description line, excludes an `always-on` member, or when `interface-design` lacks a `planning` member; it reports user and repository profile plugins that are not installed and installed plugins no profile names. The repository gate `scripts/check-plugin-profiles.sh` runs it in CI.

### Removed

- The `core` bundle plugin leaves the catalog in this release; profiles replace it. The `always-on` profile is part of every profile, and `apply build` switches on the plugins for writing, reviewing and shipping a change. An installed copy of `core` keeps working until you uninstall it; drop its `enabledPlugins` entry, since the marketplace no longer publishes it.
