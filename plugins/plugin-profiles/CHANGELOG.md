# Changelog

All notable changes to the `plugin-profiles` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.8] - 2026-11-23

### Fixed

- Two applies to one folder at the same time no longer lose a record: an apply saves its record only while the record file still holds what it read, so an apply that another apply finished first re-plans over that apply's record instead of overwriting it, and `clear` can still put the file back.

## [0.9.7] - 2026-11-22

### Fixed

- An apply whose settings write fails now undoes its record only while the record file still holds the one it wrote, so a second apply that saved its record in between keeps it, and `clear` and `reset` can still undo that apply.

## [0.9.6] - 2026-11-22

### Fixed

- On Windows, `launch` prints a PowerShell line (`Remove-Item Env:...; claude --settings ...`) in place of the `env -u` line Windows cannot run; `argv` keeps its shape for scripts that build their own start. Inline `--with` JSON with no profile now passes as a session file, since Windows PowerShell 5.1 strips the quotes inside it.

## [0.9.5] - 2026-11-22

### Fixed

- A profile that excludes an always-on `optional` member is now rejected, as one that excludes an always-on `plugins` member already was. To keep such a member off, move the line to a `remove` line in your own `always-on.yaml`.
- A `remove` line in a profile file now drops an inherited `optional` member, not only an inherited `plugins` member.

## [0.9.4] - 2026-11-21

### Changed

- `plugin.json` declares the mods floor as `engines["claude-code"]`, `">=2.1.287"`. Claude Code 2.1.323 and later read it and do not install, update or load the plugin outside that range; 2.1.76 through 2.1.322 ignore it, and 2.0.15 through 2.1.75 refuse to load a manifest that has it.

## [0.9.3] - 2026-11-21

### Changed

- the shared prerequisites checker gains a latest-release mode

## [0.9.2] - 2026-11-20

### Changed

- `profiles.mjs status` and `status --json` read the installed plugins from `plugins/installed_plugins.json`, as the session-start notice does, instead of starting `claude plugin list --json`, which alone took 1.3 to 3.8 seconds. `apply`, `launch` and the install paths still read `claude plugin list` ([#17656](https://github.com/melodic-software/claude-code-plugins/issues/17656)).

## [0.9.1] - 2026-11-20

### Changed

- Reset asks about a moved repository's file as its own kind of question: Keep, then Put back, answered with `--keep-moved` and `--put-back-moved`; the folder-without-a-record flags no longer answer it, and the one question names files in a repository that moved among those it leaves to their own question.
- The profile skill's reset action shows every preview line exactly as printed before it asks anything, never a summary or paraphrase; its eval case fails a run that asks without them.
- The reset preview's line about files unchanged since an earlier reset names them (how many, the first three and how many more) and calls them files reset already handled, which stays true for a cut-off file finished while keeping a hand edit.
- Apply's preview in a repository that moved, while a record from before the move is kept, says in one line that reset puts the file back one layer per run, newest first, naming each such record and its profile.
- A cut-off file whose entries include ones an unfinished switch still owes says they hold "the values profile P wrote or its unfinished switch had yet to change"; with no such entry the wording is unchanged.

## [0.9.0] - 2026-11-19

### Added

- `profiles.mjs reset` puts every settings file a profile changed on the machine back, user settings included, behind one preview and one yes; a reset stopped part way finishes on the next run. It reads a record only from a home that can hold it, refuses a write that no longer matches the preview passed with `--preview-id`, and exits 3 when it wrote what it could and named each file it skipped. A moved repository with profiles applied before and after the move goes back one layer per reset, newest first, each run writing a file from one record only; a run that leaves an older record waiting exits 3 and says to run reset again, and after the last layer the file holds what it held before the first apply. A no to the one question keeps the recorded files and still asks each file's own question (`--keep-recorded` for a caller). A file changed by hand after a reset was stopped before its write keeps its record and gets its own yes (`--finish-cut-off`, `--keep-cut-off`), which puts back only the entries still at the profile's values, counting an entry an unfinished switch still owes until it is back at its value before the profile.
- The `/plugin-profile` picker has a **Reset** row under No profile, and the profile skill has a reset action; both show the same preview and ask before writing, and a folder without a record changes only on a yes for that folder. Each per-file question in `reset --dry-run --json` carries its answers' labels and flags and a recommended answer with a one-sentence reason (`ask.recommend`; `questionRecommend` for the one question); the picker shows it as a line before the question and the skill marks that answer `(Recommended)`.- Reset notes the bytes it left in each file it put back, so a later reset does not offer that file's own entries for removal while it is unchanged; an edit or an apply ends that.

### Changed

- Every question the `/plugin-profile` picker and the profile skill ask lists the answer that changes nothing first (Cancel, Keep, No), so the picker pre-selects it, the apply, switch and clear confirms included; Esc is that answer.
- A one-session file also names each installed plugin of every other marketplace some profile governs, at its value at launch, so a reset or another profile elsewhere never changes that session's plugins; a later `/plugin` toggle of such a plugin reaches only sessions started after it.

### Fixed

- The `/plugin-profile` picker's second write after a reload runs `apply --finish-pending`, which writes only while the folder's switch is still pending, so it never writes back a profile cleared or reset since, including one cleared or reset while it lists the installed plugins: it saves its record only while the pending record it read is unchanged.

## [0.8.0] - 2026-11-19

### Added

- A shipped `improve` profile for targeted improvement of existing code: find one improvement, make it, test it and open the pull request, with 13 plugins in place of the 38 of `harness-upkeep`.

## [0.7.0] - 2026-11-18

### Changed

- `save` writes every list of a profile file (`plugins`, `optional`, `remove`, `exclude`, `hide_skills`) in alphabetical order, in its preview as in the file. The shipped profiles are sorted the same way, and `check` fails a shipped list out of order, naming the first name out of place. A profile file you already have changes only when `save` next writes it.

## [0.6.1] - 2026-11-18

### Fixed

- treat a Desktop WSL session as Claude Desktop

- On Windows, `start` and the commands that list plugins or sessions no longer print Node's DEP0190 warning: they run the `claude.exe` on PATH without a shell.

- A second `/plugin-profile`, with or without a profile name, while the picker pane is open is refused with a line saying a pick is already open, so it can no longer start a second switch; the open pane's pick still completes. A pick in the pane is refused when a switch from before is still waiting for its reload, and the picker reads whether its pane is open from Claude Code, so a reload of the plugin while the pane is up no longer loses track of it ([#16816](https://github.com/melodic-software/claude-code-plugins/issues/16816)).

## [0.6.0] - 2026-11-18

### Added

- A shipped `native` profile: Claude Code as it ships, with every plugin of the marketplaces it and `always-on` name switched off, guardrails and the other always-on plugins included, and only the profile switcher kept on as the way back. Its preview, in a terminal, in `/plugin-profile`, in `start` and in `launch`, names the always-on plugins it switches off, says guardrails is among them only when it is, and names any always-on plugin that stays on with why: the profile switches it on, the repository's settings enable it, or managed or folder settings pin it ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).
- A profile key, `always_on: false`, makes a profile's own lists the whole set, without `always-on.yaml`'s; such a profile may also exclude an always-on member. Its own `plugins` list is the whole set: an always-on plugin from a marketplace only `always-on` names is switched off too. Shipped and user-level files can set it; a repository file that sets it is ignored and the preview, `check` and `save` say so ([#17038](https://github.com/melodic-software/claude-code-plugins/issues/17038)).

## [0.5.0] - 2026-11-18

### Added

- `profiles.mjs start [<profile>] [claude arguments]` starts `claude` in a profile: it writes the one-session file, drops the inherited profile variables, passes your other arguments through, and exits with claude's status. With no profile it asks which, by number, and refuses when nobody is there to answer ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- A resumed session keeps its profile: the session-start hook records the profile each session runs in, `start --resume <id>` resumes in it, `-c` passes through unchanged so it continues the conversation plain `claude -c` would, and a session resumed or continued with plain `claude --resume` is told the command that resumes it in its profile ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `start --claude-args [claude arguments]` takes `--profile <name>` (or `--profile=<name>`) from anywhere among the words and hands every other word to `claude`, so a dotfiles `claude` shell function can take `--profile build` (Claude Code itself has no such flag) and make `claude --resume <id>` resume in a profile; with no profile and no resume flag it runs `claude` with the words unchanged. `--profile` also works without `--claude-args`. ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- The session-start hook of the installed plugin writes its own folder to `~/.claude/plugin-profiles-state/root`, rewriting it only when it changes, so the `claude` function finds the plugin without asking `claude plugin list`; a worktree or `--plugin-dir` copy never writes it ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).

### Changed

- `--for folder` now writes the `.claude/settings.local.json` Claude Code reads: in a git repository, the one at the main checkout's root, for every worktree and subdirectory; on Windows, outside git, or where the repository root is your home folder or not yours, the folder's own file. `status` says when the file is read by every worktree, and a folder switch names the live sessions in every worktree of the repository ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- The record of what apply wrote now lives in the repository's `.git/plugin-profiles/` for a folder in git and in `~/.claude/plugin-profiles-state/` for user settings, so it survives a lost plugin data folder; a record already in the data folder is still found, and the next apply moves it ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).

### Fixed

- A copy of the tool outside the plugin cache, such as a worktree or `--plugin-dir` copy, run from a shell that another plugin's `CLAUDE_PLUGIN_DATA` reached, no longer writes its records and session files into that plugin's data folder, where the installed copy's `status` and `clear` could not find them ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- A one-session file now names every skill a profile can hide, so a skill a folder profile hides no longer stays hidden in a one-session profile that keeps it ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `clear` names each entry edited since the apply that it is about to put back, with its value now, the profile's and the one it restores ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `status` names a profile an earlier version applied to a worktree's or subdirectory's own `.claude/settings.local.json` as partly in force, and `clear --for worktree` puts that file back ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `clear` with no record, in a file that still holds plugin or skill entries, says it cannot tell which a profile wrote and changes nothing, instead of saying there is nothing to clear ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `start` takes `always-on` by name and lists it in the picker; a SIGTERM or SIGHUP sent to `start` reaches `claude` and `start` waits for it to exit; on Windows `start` runs `claude.exe` without a shell, so an argument with a space or `&` arrives whole ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- The `/plugin-profile` confirm names sessions in a one-session profile apart, as keeping theirs, instead of saying every session in the folder gets the new profile, and gives each session's id prefix beside its name. A session resumed without its one-session profile counts as following the folder again ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- `status` and the start notice in a linked worktree name the entries its own `.claude/settings.local.json` sets that the root file does not, when no profile wrote that file, so a plugin turned off there has a named file to edit; `clear` leaves such a file alone ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- A switch's preview says the plugins it turns off are written off in a second write, after the next reload, and counts that write, instead of "Left on until the next apply" beside a write count of 0 ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- `clear` that removes a settings file the first apply created also removes the `.claude` folder that apply created, when nothing else is in it ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- `status` says every worktree reads the folder file only when the repository has a linked worktree, not in a submodule, a bare repository's worktree or a repository with none ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
- The session-start notice prints one short line per fact: in a one-session profile, the profile and the `claude --resume <id>` command with the session's own id; for a folder profile, the file it applies from; the surface only off the CLI. A `/resume` inside a terminal in another profile says the session's record now restores that profile ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).

## [0.4.1] - 2026-11-17

### Fixed

- `/plugin-profile` answers as soon as the picker pane opens and runs the pick from the pane, so it no longer overruns its hook's 10-second budget and every outcome line prints ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- The picker pane draws every profile and **No profile** as a row at once instead of a closed drop-down; a row's whole description shows under the pointer, and the focused row's under the list ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- The preview names the plugins a switch turns off once: "Left on until the next apply" counts them, and so do the closing and in-force lines ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).
- `status` and `clear` find a profile another copy of the plugin applied, such as a `--plugin-dir` copy whose record sits in `plugin-profiles-inline`, instead of saying nothing is recorded ([#16818](https://github.com/melodic-software/claude-code-plugins/issues/16818)).

## [0.4.0] - 2026-11-17

### Added

- `/plugin-profile` picks from one pane listing every profile and **No profile**, with a Cancel button: a Select, or a button per entry on mobile, which may not draw a Select; where no pane can be placed it falls back to the paged question dialog ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).
- `/plugin-profile` offers **No profile**, which clears this folder's profile behind the same preview and confirm as a switch, then reloads at the next turn's end; a folder with no profile says so and how to drop an earlier profile's plugins still loaded ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).

- `clear --dry-run --json` prints whether a profile is recorded, the one-session profile the running session keeps, and the preview lines; in a session started in a one-session profile, `clear` says that session keeps it ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).

### Fixed

- `/plugin-profile` shows the profile list and the preview one line each, and counts the plugins left alone instead of naming them, so nothing renders as one cut-off paragraph; the confirm no longer names the running session among the other sessions in the folder; its closing line carries no doubled `plugin-profiles:` prefix and names the plugins left loaded only when the switch turned some off; and after Apply it says to send any message or run `/reload-plugins` to load the change ([#16747](https://github.com/melodic-software/claude-code-plugins/issues/16747)).

## [0.3.3] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [0.3.2] - 2026-11-17

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

## [0.3.1] - 2026-11-17

### Fixed

- A one-session file sets `SESSION_SETTINGS_FILE` to its own path, so plugin-diagnostics and harness-ops skip the prerequisite notices of plugins the profile turns off, and `launch` clears an inherited one ([#16673](https://github.com/melodic-software/claude-code-plugins/issues/16673)).

## [0.3.0] - 2026-11-16

### Added

- `launch --json` with a profile carries `enabledPlugins`: each plugin any settings layer names, on or off as the session will start with it, the session file read as the session layer, so a plugin the repository, managed or user settings enable is reported though the profile writes no entry for it. It is reported under `--dry-run` too, so a launcher can check what a session will start with before it starts one.

## [0.2.2] - 2026-11-16

### Changed

- The `always-on` profile no longer lists `context-budget`, whose settings-write ask now runs in guardrails; `context-budget` moves to `harness-upkeep`.

## [0.2.1] - 2026-11-16

### Changed

- The `always-on` profile lists `session-telemetry` and `plugin-diagnostics` in place of `harness-ops`, which moves to `harness-upkeep`.
- Setup's hook-plugin question (phase 4) names `session-telemetry` and `plugin-diagnostics` among the plugins it asks about.

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.

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
