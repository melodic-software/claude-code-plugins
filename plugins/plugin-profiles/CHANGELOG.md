# Changelog

All notable changes to the `plugin-profiles` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-11-16

### Added

- `launch [<name>] [--folder <dir>]` writes the one-session file for a folder and profile and prints the `claude` command that starts a session in it, asking nothing and changing no settings file. With no name it takes this session's profile, else the folder's; with neither the command carries no profile. The command always clears an inherited `PLUGIN_PROFILES_SESSION`. `--with` takes a launcher's own settings (a JSON object or a file) and writes one file holding both, since `claude` keeps only the last `--settings`. `--unattended` stops when the profile switches on a plugin missing a required prerequisite. `--dry-run` does every check and prints the result but writes no file. `--json` prints the result with the words a launcher runs before its own arguments. An empty `PLUGIN_PROFILES_SESSION` counts as unset everywhere it is read. A session file no launch has written for 30 days is removed by the next launch. Launch works from any surface, since the session it starts is a CLI session, and each session file sets `PLUGIN_PROFILES_SESSION_FILE` to its own path, so `status` names the file a session was started with, merged or not.
- `/plugin-profile`'s confirmation names the other live sessions in the folder (from `claude agents`), which get the new profile at their next reload or start, and says to start one with the launch command to give it its own. It still applies on Apply. `apply --dry-run --json` carries them as `othersInFolder`.
- `status` prints the command that starts another session here in the profile in force, which a handoff uses as its restore line.

### Changed

- The one-session file is one per folder and profile, so sessions in two folders with one profile no longer share a file.

### Fixed

- A new git worktree whose `.claude/settings.local.json` was copied from the main worktree now takes the main worktree's folder profile when the copy still holds every entry that profile wrote, so `status`, the session-start notice, `clear` and `launch` with no name see the profile there instead of reporting none. Reading it there writes nothing; the next `apply` in the worktree records it.

## [0.1.1] - 2026-11-16

### Fixed

- `check` reports a user or repository profile file it cannot read, naming the file, and checks the other levels instead of stopping; a shipped profile it cannot read still stops the check with the file named.

## [0.1.0] - 2026-11-16

### Added

- The `plugin-profiles` plugin, on by default: named profiles of plugins to switch on, one YAML file each, shipped in `profiles/`, per user in `~/.claude/plugin-profiles/` and per repository in `docs/conventions/plugin-profiles/`; a same-named file at a higher level extends the one below with `plugins` and `remove` lines. A repository file cannot switch off an `always-on` member: apply ignores that line and the preview names it, and marks what only a repository file switches on or hides. Ships seven profiles: `always-on`, `discovery`, `planning`, `interface-design`, `build`, `review` and `harness-upkeep`, each with a description line saying when to pick it.
- `scripts/profiles.mjs apply <name> --for folder|initial|session` previews the plugins it switches on and off, pinned and missing plugins with their install commands, and the plugins of other marketplaces it leaves alone, then writes only the `enabledPlugins` and `skillOverrides` entries of `.claude/settings.local.json`, user `settings.json` or a one-session `--settings` file, all or nothing, on `--yes` or a yes at the prompt. A plugin it switches on with a missing required prerequisite is named with the tool, its install line and the consequence, and `--yes` alone does not apply it.
- `status` names the recorded profile, each entry that differs, plugins installed since and an unfinished switch; `clear` previews, then on `--yes` or a yes at the prompt restores every entry to its value before the first apply and removes a settings file the tool created; `inventory` lists installed plugins with their dependencies and what each ships.
- A SessionStart hook prints the same notice where a profile was applied, naming the profile, what differs, plugins installed since, an unfinished switch and the surface; it reads installed plugins from disk, never starts `claude`, and prints nothing in a folder with no applied profile.
- `apply --for session` sets `PLUGIN_PROFILES_SESSION` in the generated file and says to pass `--settings` again on resume. Apply and status name the surface: VS Code and Claude Desktop refuse a one-session apply and offer the folder level, cloud and Claude Desktop WSL sessions report that profiles do not apply and write nothing, and an unrecognized surface reads "surface not detected" and allows the folder level only.
- The `remember_folder_profile` option (on by default): off makes every session start from the initial profile, refuses a folder apply, and names a folder profile left from before as not in force.
- `/plugin-profile` switches the folder's profile in a running session without a model turn: a picker of the profiles, the `apply --dry-run` preview, and a confirm. It writes the entries that switch plugins on, runs `/reload-plugins` once when the next turn ends, then writes the entries that switch plugins off, which stay loaded until the next session start. A switch that turns on a plugin with an MCP or language server names it and says the next message re-reads the whole conversation. It refuses when `remember_folder_profile` is false or the session runs from a one-session file, saying how to start a session in that profile. The command needs Claude Code 2.1.287 or later; `apply` does not.
- `list [--json]` names the profiles a folder apply can use with their descriptions; `apply --dry-run --json` prints the preview as one object.
- `check` fails when a shipped profile names a plugin missing from the catalog, uses another marketplace than the catalog's name (naming the fix), lacks a description line, excludes an `always-on` member, or when `interface-design` lacks a `planning` member; it reports user and repository profile plugins that are not installed and installed plugins no profile names. The repository gate `scripts/check-plugin-profiles.sh` runs it in CI.
- `/plugin-profiles:profile` runs `apply`, `status`, `clear`, `check` and a guided `setup`, showing every change before it makes it. `setup` lists the installed plugins and their skills and this machine's usage history, asks about your work and, for each plugin that ships hooks or a mod, always on or per profile, then proposes profiles to save at user or repository level. Told to skip the questions, it still lists the installed plugins and, for a profile member that is not installed, previews its install and asks first.
- `usage` lists skill and plugin use from the counts Claude Code keeps, or says no usage history was found; `inventory` now lists each plugin's skills.
- `save <name> --level user|repository` writes a profile file after printing it; `install <name@marketplace>` installs a missing plugin at user scope only on a yes, only from a marketplace the machine already knows and never for a plugin only a repository profile names, then switches it off in user settings unless the initial profile includes it.

### Removed

- The `core` bundle plugin leaves the catalog in this release; profiles replace it. The `always-on` profile is part of every profile, and `apply build` switches on the plugins for writing, reviewing and shipping a change. An installed copy of `core` keeps working until you uninstall it; drop its `enabledPlugins` entry, since the marketplace no longer publishes it. `core` installed `guardrails`, the guard hooks that block secret leaks and destructive commands: before you uninstall `core` and run `claude plugin prune`, enable `guardrails` directly, or prune removes it.
