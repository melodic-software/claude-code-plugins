# Changelog

All notable changes to the `app-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.20.0] - 2026-10-31

### Added

- `/app-control:drive` eval cases check that an unattended animation capture runs nothing on an app this run did not launch, and reports a capability gap with no stand-in tool when the control skill names none.

- `/app-control:drive capture --kind animation` records an animation's per-frame state (each animation's target, property, from and to values, current value, duration, easing and progress) with the tool the control skill names for the kind, only in an app this run launched with seeded data.

## [0.19.0] - 2026-10-31

### Added

- The control-skill contract gains `## Mask` ([#11387](https://github.com/melodic-software/claude-code-plugins/issues/11387)): mask lines (`- <label> | <regex>`) or `none: <reason>` for what a `screenshot` or `video` must hide, and an optional `values:` line naming the config fields or read-only `cli/` commands that give the literal values to look for. A `screenshot` or `video` Capture command applies the mask lines and writes an `<artifact>.txt` sidecar holding the text the capture still shows.
- `/app-control:drive` writes redacted `report.public.md` and `report.public.json`, then scans each sidecar and both public reports for the `values:` values and a generic credential pattern, with line wraps joined and box-drawing characters stripped. `report.json` gains `capture_count`, `artifacts` (each with `mask`: `applied`, `none-declared`, `not-checked` or `hit`, and `publishable`) and `publishable`, the paths safe to upload. A hit, a missing sidecar, no `## Mask` line or an unresolved value keeps a file out; a raw capture and any file with a `secrets_mark` entry are never publishable.
- A `## Launch` command may name `<changed files>`: one argument per file in the run directory's `affected.json`.
- `/app-control:map check` reports a hub whose `## Capture` records a `screenshot` or `video` and whose `## Mask` holds no mask line, under the new `mask-missing` rule, and `/app-control:map create` writes a `## Mask` for such a hub.

## [0.18.0] - 2026-10-31

### Added

- `/app-control:drive affected --base <ref> [--head <ref>]` maps a diff to the control skill's features and writes `affected.json`, launching nothing ([#11384](https://github.com/melodic-software/claude-code-plugins/issues/11384)). `scripts/affected_features.py` does the matching. With no control skill it writes empty features and the note `No control skill: nothing matched`.
- `--trusted-root <dir>` on every drive action reads control skills only from `<dir>` and from plugins whose folder sits under it, so a checkout under test cannot supply its own control skill.

### Changed

- The control-skill contract fixes the `sources` glob syntax: `**` matches across `/`, `*` and `?` match within one path segment. A plugin control skill's globs resolve against the root of the repository under verification.

## [0.17.12] - 2026-10-30

### Changed

- A module `README.md` that the hub indexes in place of its features now lists each feature under `## Sub-features` as a full index line (path, entry-point count and `sources` globs). A caller that matches the module's hub line reads those lines to find the exact feature a changed file touches, and `/app-control:map refresh` keeps both sets of lines true. Each feature's own `README.md` is the source of truth for its entry points; the module `README.md`'s copy is rewritten from the features when they disagree, and refresh rewrites it in the same edit that changes a feature's entry point or its `driven` mark.

- The control-skill contract now states four rules it was missing ([#9507](https://github.com/melodic-software/claude-code-plugins/issues/9507)).
  - A module folder's `README.md` indexes the features under it, and the hub's index then names it in place of a line per feature.
  - A drive through one entry point never marks another `driven`.
  - A journey belongs to the control skill of the app where the user starts and ends it. The pages it crosses in an integrated app are steps that app owns, and every service it depends on is a dependency service that Ready checks.
  - The server tier's Capture rows record the app's own process, and the `logs` row may name a counters recorder such as `dotnet-counters collect`.

## [0.17.11] - 2026-10-30

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.17.10] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.17.9] - 2026-10-30

### Fixed

- `/app-control:drive` now keeps the per-run count of the control-skill contract's Sign-in floor, which the CLI cannot keep because it holds no count between calls. Drive calls `cli/ sign-in <account>` at most once per account in a run, unless committed config allows more. A failed sign-in ends every step that is not a finally step, and drive tries no other account in its place.

## [0.17.8] - 2026-10-30

### Changed

- **The control-skill contract states five more rules for a generated control skill** ([#11127](https://github.com/melodic-software/claude-code-plugins/issues/11127)). A feature is a user's goal and a sub-feature is a state or branch inside it. A `not driven: <reason>` entry point names what would make it drivable. UI that differs by tenant or configuration is a named precondition in `## Drive` or a step whose selector matches every variant. A project's auth bootstrap, when it has one, runs the mapped sign-in steps from `shared/` or from the integrated app that owns sign-in, so sign-in selectors live in one place. A feature that signs out runs in a throwaway browser session, never in the saved one, and signs in there within the Sign-in floor's one attempt per account.

## [0.17.7] - 2026-10-30

### Fixed

- **A command-file control skill keeps its feature files outside its commands folder** ([#10085](https://github.com/melodic-software/claude-code-plugins/issues/10085)). The control-skill contract's Hub now says where `features/` sits for a control skill shipped as a `control-<app>` command file: in `control-<app>/` beside the top-level commands folder it loads from, `<base>/control-<app>/features/<id>/README.md`, where `<base>` is, for example, `.claude`, a skills-folder plugin's folder or a plugin root. That folder is the command file's base directory, holding its `shared/`, `cli/` and `config/` too. `/app-control:drive` takes that folder as the command file's base directory and resolves features there, never in the commands folder, where every Markdown file loads as a command and several commands would share one `features/` tree.

## [0.17.6] - 2026-10-29

### Fixed

- **An elevated capture runs the script text the person saw, never the file the builder wrote** ([#10518](https://github.com/melodic-software/claude-code-plugins/issues/10518)). After the yes, `/app-control:drive` feeds the builder's printed output to `sh -s` in a quoted heredoc. A process running as the person's uid could rewrite the written file between the display and the run. `build_capture_script.py` now prints its process lines as shell comments, so its whole output is the script. With `--elevate` it writes the file as a mode 0600 record that nothing runs. The script body is one group with stdin from `/dev/null`, so the shell reads all of it before it runs any of it, and a recorder that reads stdin cannot read the rest of the script. A script built without `--elevate` still runs from its 0700 file. The builder now refuses an unprintable character, such as a bidi override, in `--write`, `--capture` or a recorder argument, where it would make the shown text read differently from what runs. `pid-binding.md` states the residual limit: a process with the person's uid can still act as that person in other ways.

## [0.17.5] - 2026-10-29

### Fixed

- A control skill's Ready command must now fail when the instance is unfit. The contract's new "The Ready command" section and `/app-control:map`'s Generate step require each check in Ready to exit non-zero when it fails, so a listing such as `docker ps` ends in `grep -q` on the expected row instead of passing with no rows. Map's proof runs Ready once more with the app stopped and records that it exits non-zero, read from the new `ready.exit` field of `/app-control:drive`'s report. `/app-control:map check` reports a `ready-listing` finding for a Ready command whose last stage is a bare listing, and create fixes each one before its proof.

## [0.17.4] - 2026-10-29

### Fixed

- `/app-control:map refresh`: a pass now switches to the upkeep branch, creating it from the default branch or merging the default branch into it, before the source wave and the live pass, so its corrections describe the tree the upkeep pull request ships. The dirty-tree checks and their blocked outcomes, and a legacy conversion's dirty-map check and attended ask, run before that switch, a refused merge is aborted, and a ticket-branch pass still stays on its branch. Every pass, blocked early or not, switches back to where it started, and a clean pass records its skip state only after that return.

## [0.17.3] - 2026-10-29

### Fixed

- **The `map-refreshes-each-control-skill` eval case passes a correct refresh plan.** Its judge failed every correct reply: the criteria asked the reply to commit and switch, while the prompt forbids both, so the judge failed a plan for not running; and they required each upkeep branch cut from `main`, where the refresh rules cut it from the fetched default-branch tip. The criteria now judge the plan, accept the fetched tip and the documented fallback when no pull-request tool is available, and still fail a shared branch or pull request, a second branch cut from or merging the first, a missing return to `main`, or asking which skill. The scaffold now adds the `origin` remote the pass fetches from, and the prompt states it.

## [0.17.2] - 2026-10-28

### Fixed

- **The `map-refreshes-each-control-skill` and `map-reports-legacy-upkeep-branch` eval cases state a clean working tree in the prompt.** A stray file in the eval workspace, such as a `.gitconfig`, no longer counts as an untracked change that blocks the refresh, and each scaffold keeps `.gitconfig` out of `git status`. Each case's description now also says a run needs `--scaffold`. Without that flag the workspace stays empty and both cases score near zero.

## [0.17.1] - 2026-10-28

### Fixed

- `/app-control:map refresh` started on a ticket branch commits its doc-drift corrections on that branch and opens no upkeep pull request, so the ticket's pull request carries them and they merge, or are dropped, with the code they describe. Before, the corrections went to an upkeep pull request cut from the default branch, which could merge ahead of the ticket or without it. A pass started on the default branch keeps the upkeep branch and its one pull request. On a ticket branch, a legacy-map conversion still rides the upkeep pull request and a flat-to-folder conversion is blocked until it runs from the default branch; a detached HEAD off the default branch's tip commits nothing.

## [0.17.0] - 2026-10-28

### Added

- The control-skill contract has a size budget: 16,000 characters for the hub and 4,000 for each feature file, counted the way `/skill-quality:check listing-budget` counts. `/app-control:map check` reports a file over its budget with the new `size-budget` rule, and `/app-control:map create` reports any it wrote as a warning that stops nothing.

## [0.16.1] - 2026-10-28

### Fixed

- `/app-control:map refresh` switches back to the branch it started on after every pass, not only between control skills in a multi-skill pass. A one-feature refresh called from `/testing:run-e2e` or `/verification:confirm` on a ticket branch no longer leaves the caller on `control-skill-upkeep/*`. From a detached HEAD, such as a CI checkout, it returns to the starting commit.

## [0.16.0] - 2026-10-27

### Added

- `scripts/build_capture_script.py`, with `scripts/build_capture_script.test.sh` beside it, builds the shown capture script for `/app-control:drive`. It checks the launch record's pid, uid, start time and command line hash against `/proc` and the caller's uid, resolves a wrapper's one child with `--child`, or binds a pid the person names with `--attach-pid`. It writes the script to a new file and prints each checked process and the script. The script reads `starttime` from the fields after the last `)` of `/proc/<pid>/stat`, rechecks every pid before the recorder and again after it exits, and deletes the capture and exits 3 on a difference. An elevated recorder that writes a `<file>` writes it into a new directory the elevated user makes; the script copies it to the capture path as the user running it, so the captured process cannot redirect the elevated write through a symlink.

### Changed

- `/app-control:drive` runs a pid-bound capture's recorder only through the built script and shows the builder's full output before the yes. A `cpu` or `heap` recorder that takes a pid now gets the same binding and recheck as `threads`. An elevated attach records the attached pid's uid, start time and hash when its script is shown, and the script rechecks them.
- **Breaking on hosts other than Linux:** a `cpu` or `heap` capture whose recorder takes a pid, and an elevated attach, now record `blocked: pid binding covers Linux only, not <platform>` on macOS, Windows and any other host that is not Linux, since the binding reads the Linux process table.

### Fixed

- On macOS and Windows a `threads` capture records `blocked: pid binding covers Linux only, not <platform>`. Before, it was blocked with no reason named. An unattended capture whose launch record holds an invalid pid now records `blocked: launched process no longer matches` before `blocked: capture needs elevation`.

## [0.15.0] - 2026-10-27

### Added

- The control-skill contract's hang (`threads`) row now names an all-thread dump command for JVM (`jcmd` `Thread.print`), .NET (`dotnet-stack report`) and Linux native (`gdb` `thread apply all bt`), each against the launched `<pid>`, and reads n/a for Node.js. Each new tool has a manual pointer with an as-of date and a recheck trigger. Go stays "not yet": its goroutine dump is served on the app's own endpoint, which drive's pid binding cannot hold to the launched process.

## [0.14.1] - 2026-10-27

### Fixed

- `/app-control:drive` names how to get `python3` for the integrated-app pin check: app-control now declares it in `prerequisites.json`, and drive runs the bundled checker for the install command when it is missing.

## [0.14.0] - 2026-10-27

### Added

- The `app-control:source-reader` agent, whose tool list holds Read, Grep and Glob only, for the `/app-control:map refresh` source wave.

### Fixed

- `/app-control:map refresh` sends its source wave through `app-control:source-reader`, so a subagent reading app source can no longer edit, write or run anything; before, the read-only limit was only an instruction in its prompt. When the agent does not resolve, the pass is blocked rather than sent through another agent. Each prompt now opens with the untrusted-content framing and quotes every repository value inside the item-content-trust fence. The working-tree tripwire is named a backstop, and the report states what it cannot see: writes under `.git/`, to ignored paths and outside the checkout.

## [0.13.0] - 2026-10-27

### Added

- `/app-control:drive`'s `report.json` gains `secrets_mark`: one entry per raw capture, and per report file once it holds a command line, with its path, the "may hold secrets; do not commit" mark and whether the run directory sits unignored in a git working tree.

### Changed

- `/app-control:drive`'s Pid binding rules move to the `drive/reference/pid-binding.md` spoke with only their links adjusted; the hub's launch row, `threads` capture row, `threads` rule and cleanup rule link it.

### Removed

- The control-skill contract's manual pointers for dotnet-stack, GDB `thread apply all` and `GOTRACEBACK`, since no `threads` row names those tools. The dotnet-trace and dotnet-gcdump pointers stay.

## [0.12.2] - 2026-10-27

### Fixed

- `/app-control:map refresh` takes a listed pull request as the upkeep pull request only when it is from the repository itself. A fork's pull request on a same-named branch makes the outcome blocked and is named in the report, and the pass pushes nothing.

## [0.12.1] - 2026-10-27

### Added

- Eval cases for a plugin control skill found only through a manifest path: a plugin eval case with a skills-folder plugin whose `commands` map points `control-shop` at a file outside `commands/`, and skill eval cases with a listed plugin whose `commands` path names a non-default folder beside a stale `commands/` file, and one whose `skills` path names an extra folder; and a plugin eval case where a skills-folder plugin's control skill, the repository's only one, is used as a project control skill when no app is named.

### Fixed

- `/app-control:drive` now finds a plugin's control skill at a path the plugin's manifest names. For each listed plugin it searches the skill and command files the plugin loads from its default folders and its manifest's `skills` and `commands` keys, located as the manifest reference says, keeps or drops a `commands` map entry's `source` file by the entry's key, and reads no path outside the plugin folder. A plugin kept in the repository's skills folder is searched the same way and stays a project control skill, so it still beats an installed plugin's control skill for the same app. Before, such a control skill was missed and drive fell back to its no-control-skill recipe.

## [0.12.0] - 2026-10-27

### Added

- The control-skill contract gains an "Environments" section. Environment entries (`url`, dependency `services`, `extends`, a `writes` policy per write of `never`, `attended` or `unattended`, and `production: true`) come only from `config/defaults.json` committed at HEAD. The local, environment-variable and flag layers may select an environment by name, never add or redefine one; the driver CLI refuses such a layer with exit 4. An entry that extends a production entry stays production.
- The contract gains an "Integrated apps" section: a system whose pages a journey crosses, such as a separate identity server, gets its own control skill, and its steps are included by reference as `<app>:<path>`. The `checkouts.<app>` setting holds the path of another repository's local checkout; when it is unset or wrong, the run stops before launching and names the setting and the repository to clone. Committed config pins each such app by commit SHA in `pins.<app>`; the run stops before launching, and again before each included `cli:` call, that app's launch and its Ready, unless the checkout holds that commit, its HEAD and its control skill folder match it byte for byte (no index flags, filter attributes, replace refs, fsmonitor or inherited `GIT_*` variables, no symlink out of the folder; CRLF is the only normalization) and the folder holds no untracked or ignored file other than its `config/local.json`; that app's config and floors are read at the pin. `/app-control:drive` runs this check with the bundled, tested `scripts/verify_pin.py`. An unset pin tells the person to commit `pins.<app>`, for example through `/app-control:map`, which writes a pin only for a commit on the default branch of the hub line's repository URL. An included `cli:` step runs the owning app's `cli/` with that app's config, a minimal environment holding that app's credential variables (never the hub's own or a loader or interpreter variable), `--environment` set to the mapped environment (checked against its `--json`), and `--kind` set to the include's kind. An included step runs under the owning app's committed floors, enforced by its CLI; the including control skill can tighten it only through the include's `kind` or by leaving it out. A driver CLI writes nothing inside its control-skill folder, so the untracked-file check does not stop a second run, turns bytecode off itself, and loads code only from that folder plus dependencies pinned with integrity hashes by a lockfile there, installed outside the folder into a new directory for each run.
- `<environment url>` and `<<service> service url>` placeholders in Launch and Ready are filled as one argument, validated as an http(s) URL with no shell metacharacters, and run without a shell; a `.cmd` or `.bat` program is refused.
- `report.json`'s `launch` is a list with one entry per launched app, and cleanup stops each. A capture binds to the entry whose `app` is the app of the control skill owning the Capture row it uses; more than one such entry is `blocked:`, naming the apps.
- `## Capture` can hold one row per tier (such as browser and server). `/app-control:drive capture` records each tier's row with its own tool, and the tier is part of the artifact name.
- `/app-control:drive ready` checks each dependency service of the selected environment: that it answers, and, where the app shows its target, that the app sends to it. `report.json`'s `ready` gains `environment` and `services`.
- `/app-control:map create` asks for each related system's repository and for which environment is production. It writes environment entries and an Integrated apps hub line, and writes nothing into another checkout except the objects and `FETCH_HEAD` that the Pin rule's fetch writes.

### Changed

- **Breaking: a new Write grants floor covers every write, in every environment.** Every write command takes `--step <id>`, the step's unprefixed id (or the command name without a steps file). The CLI binds the key to the step's `cli:` command at HEAD (or the command of that name), refuses a command whose non-reserved arguments differ, and applies the strictest committed grant among every key bound to that command; a missing or unknown id, an unlisted one, `never`, or `attended` without `--attended` exits 4. A write to an environment not marked production that ran before without a grant is now refused until committed `writes` lists its key. External systems take a `systems` entry per environment, committed only.
- **Breaking: step ids are unique across all of a control skill's own steps files**, not only within one run, and no step id equals a `cli/` command name. A repeated id stops the run before anything starts.
- **Breaking: every driver CLI command accepts `--kind write` and `--kind send`**, which only tighten: the command is then held to that kind's floors as well as its own. A CLI that rejects the flag fails every step an include marks with a `kind`.
- The Production floor now states that `--yes` needs `--attended`, so no config turns on an unattended production write.

## [0.11.0] - 2026-10-26

### Added

- The control-skill contract gains a "Steps files" section: a feature may keep its Drive steps in a machine-readable file whose format stays the project's choice. Step ids are unique after includes expand and use letters, digits, `-` and `_` only; a repeated or malformed id stops the run before anything starts. Includes stay inside the control skill's own directory. An include can carry `prefix` (one file included twice with unique ids), `with` (parameter values for that include only; an undeclared name stops the run), `kind` (added to every included step, never removed) and `finally` (steps that run after a failure, where a write's reset goes). An optional step whose target is absent is recorded as skipped, with no retry or wait.
- `/app-control:drive` reads a feature's steps file as data: it expands includes and checks ids before launching, reports each step by id, records an absent optional step as `skipped: optional`, and runs the finally steps after the others, failed or not. Each such step in `report.json` carries its `id`, an `outcome` and, for a finally step, `finally: true`.

### Fixed

- `/app-control:drive` and `/app-control:map` name each reference file they send the model to by its full plugin path, so a run reads it directly and does not search the plugin directory for it.

## [0.10.0] - 2026-10-25

### Added

- `/app-control:map` create and refresh place a lesson learned while driving by its scope: a lesson about one feature goes in that feature's `## Gotchas`, one that holds for every feature goes in a new optional `## Gotchas` section of the control skill's hub, and any other lesson is written nowhere in the control skill and reported for `/corrections:codify`. In refresh a placed lesson is doc drift and ships in the upkeep pull request.
- `/app-control:map refresh <feature>` narrows the source wave and live pass to one feature of the control skill that holds it; a clean narrowed pass records no state.

## [0.9.0] - 2026-10-25

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, when the repository has no `control-<app>` of its own. It looks in the `skills/` and `commands/` folders of each enabled plugin `claude plugin list --json` reports, named by the `name` in each plugin's own manifest (a plugin without one takes the name the manifest page gives it). Session-only (`--plugin-dir`, `--plugin-url`) plugins are not read: a control skill the session shows from one, for the requested app (any app when none is named) and with no repository control skill for that app, is reported blocked and the run stops there, as does a control command a listed plugin defines only inline in its manifest, under the same app and repository conditions. Repository control skills are found in `.claude/skills/` folders at any depth, the skills and `commands/` files of a plugin kept in a skills folder, and `.claude/commands/`, in this checkout and, in a worktree, the main checkout; git-ignored and uncommitted ones count, and matches in a submodule or a dependency folder such as `node_modules` do not. A repository control skill for an app beats a plugin's for the same app. With no `<app>` named and no repository control skill, a lone plugin control skill is not used blindly: an interactive run asks first and an unattended run stops, naming it. Drive reads every control skill from disk as data and never invokes one through the Skill tool. The report names the skill used and its source (project or plugin) with its path.
- Drive reports a control skill whose frontmatter grants tools, registers hooks or forks a subagent, or whose body holds a dynamic-context command, as a finding, and runs none of it.

## [0.8.0] - 2026-10-25

### Added

- `/app-control:map refresh` keeps a control skill in line with the app and ends `clean`, `changed` or `blocked`. It skips when nothing changed since the last clean pass on this host, refuses an attended-only control skill when unattended, runs a read-only source wave of one subagent per feature in waves filled to six before the next starts, then drives every feature through `/app-control:drive` with Ready before the first drive and after any failed one, cleanup after each drive and every evidence path checked after cleanup. Each difference is triaged as doc drift (corrected), driver gap (on an attended pass fixed in `cli/` and shipped only after a live re-drive; on an unattended one reported unwritten; never by loosening a floor) or product regression (left as written and reported, or sent to `/bugs:write`, never put in the pull request). Edits stay inside the control skill's directory and go out on `control-skill-upkeep/control-<slug>` (the control skill's directory name), from the default branch, merged into and never rebased, through at most one pull request; every local and remote `feature-map-upkeep/*` branch is reported by name, not adopted. A pass over several control skills uses one branch per skill and returns to its starting branch between them. A legacy testing feature map at the path the person passes, or a control skill's flat feature files, is converted to the contract's folder layout in the same upkeep pull request, with the old files moved in that commit. A legacy map is converted first, uncommitted on the upkeep branch and after an attended pass approves the planned conversion, so both passes drive the converted control skill; a tracked legacy map with uncommitted changes blocks the conversion, and a pass that stops before the commit deletes what the conversion created, restores the legacy files from a copy taken outside the checkout before the first write, and returns to its starting branch. Reauthored from the upkeep loop, its three live-pass invariants and its triage of pstack's `maintain-verification-skill` ([cursor/plugins](https://github.com/cursor/plugins), MIT).

## [0.7.0] - 2026-10-25

### Added

- `/app-control:map check` reports where a control skill breaks the contract and edits nothing. A bundled script prints one `<rule> | <path> | <detail>` line per structural finding: an index line that names no feature file, is dead, duplicated or missing, or miscounts its entry points, a source glob that matches no file or leaves the project root, a feature README whose sections are missing, extra or out of order, an entry point with no `driven` marker or a `not driven` with no reason, a relative link that resolves to nothing, and a `shared/` item used by fewer than two features or lacking its `Why shared:` line. The model then reports any section that copies a recipe instead of naming it. The report carries no verdict word.
- The control-skill contract gains a "Shared items" section: `shared/` holds only what two or more features use, each item a direct child of `shared/` that a feature uses by naming `shared/<item>`, with a `Why shared: <reason>` line in its `README.md` or in the file itself.

## [0.6.0] - 2026-10-24

### Added

- `/app-control:map create` generates a project's control skill: it walks fixed discovery rows over the repository before asking anything, asks only what discovery left open (through `/planning:interview` when installed), writes the hub, feature folders, config, driver CLI and one pointer in the repository's source instruction file, then proves it once through `/app-control:drive` and checks the evidence survived and no process it started is alive. The control skill is written only to `.claude/skills/control-<slug>/`, where drive finds it, with every path's real location checked inside the repository. `--unattended` is a dry run that writes nothing and never guesses a safety answer. Reauthored from the create-and-prove flow of pstack's `create-verification-skill` ([cursor/plugins](https://github.com/cursor/plugins), MIT).
- The control-skill contract gains three sections: writing the driver CLI (through `/developer-experience:build-cli` when installed, else a documented script), config layered from committed `config/defaults.json` through `config/local.json`, environment variables and flags with each value's layer reported, and safety floors that ship safe (an empty recipient allowlist, one sign-in attempt per account per run, read-only production, no unattended writes), loosen only in config committed at HEAD, and are enforced by the generated driver CLI (all but the per-run sign-in count, which the caller keeps), which refuses a loosening from any other layer with exit 4. Credentials always come from environment variables and are reported by variable name and set or unset, never by value.

## [0.5.0] - 2026-10-24

### Changed

- Moved the control-skill contract to `reference/control-skill.md` at plugin level. Feature files are now `features/[<module>/]<feature>/README.md` with Parts, Sub-features, Entry points, Reset, Drive and Gotchas sections (`## States` is gone), and `/app-control:drive` resolves a feature id to its folder README, then to a legacy `features/<id>.md`.

## [0.4.0] - 2026-10-24

### Added

- `/app-control:drive capture --kind threads` records a stack of every thread for a hung process, with py-spy dump for Python named in the control-skill guidance's hang row; the other runtimes read "not yet". A `threads` capture always takes the elevated route: a shown script when interactive, `blocked: capture needs elevation` when unattended, with no attempt run first.
- Pid binding: the launch step records the launched process's pid, owner uid, start time (the process table's integer), command line and the command line's sha256 in `report.json` (`launch`). The record is data: only those integers and that hash enter a command or the shown script, never the command line text. Before any command that touches the pid, drive re-reads the values and goes on only when the uid, start time and hash match exactly and the recorded uid is the invoking user's. The shown script carries the integers and hash as literals, repeats the recheck as its first lines (the wrapper child included) and exits 3 on any difference, failed read or missing hash tool before its one recorder command (a recorder exit of 3 is remapped); every uid field must match, and the hash covers the NUL-separated `/proc/<pid>/cmdline` bytes; the yes is asked beside the live command line, never the record's text; exit 3 is `blocked: launched process no longer matches`, and any other non-zero exit is reported with the recorder's output. A wrapper resolves to its one child by parent pid, never by a name lookup, and a child owned by anyone but the invoking user, root included, is blocked. Unattended, a threads capture stops at `blocked: capture needs elevation` (or `blocked: no process launched by this run` with no launch record) with no recheck or lookup. Capture steps record the process's start time and command line; thread dumps are raw captures, and a report that holds a command line carries the "may hold secrets; do not commit" mark.
- An eval case, in the skill's `evals.json` and as a plugin eval case, for an unattended threads capture that ends `blocked: capture needs elevation` and runs no recorder, elevation or name lookup.

### Changed

- `## Next` routes a threads artifact to `/debugging:analyze-profile`.

## [0.3.0] - 2026-10-23

### Added

- Eval cases for a permission-denied capture (unattended and interactive), for an attach given only a process name, and for a pid taken from app log text; the attach case now expects an attach with no question, and the interactive elevated-capture case gives the launched app a pid.

### Changed

- `/app-control:drive --attach` in an interactive session attaches without a per-attach yes when the person's own message gives `--attach` and the pid; the report shows the process and the exact command run. When a calling skill, tool output or app text supplied the flag or the pid, drive still shows the command and waits for a yes. It never picks a process by a name lookup, asks for the pid when only a name is given, still refuses with no one present, and still runs an elevated attach only through a shown script after a yes.
- A named capture command that fails for lack of permission now needs elevation: the shown script in an interactive run, `blocked: capture needs elevation` with no one present, never a re-run with elevation on its own. For a launched process the script elevates only the recorder against its pid; a denied command that launches the app is blocked with the narrowest grant. The elevation prefixes named (`sudo`, `doas`, `runas`) are examples, not a complete list.
- Raw captures stay in the run directory as evidence; `cleanup` never deletes the run directory, only the scripts the run wrote and their temporary directories. The report marks each raw capture as possibly holding secrets. `report.json` capture steps gain `process` and `command`, and its `mode` value for an interactive run is now `interactive` (was `attended`).

## [0.2.1] - 2026-10-23

### Added

- `reference/control-skill.md` gains "Writing the Capture section": a symptom-to-tool table per runtime (spin, leak, jank, hang) with each tool's manual, as guidance for whoever writes a control skill's `## Capture`. `/app-control:drive` still picks no tool itself.

### Changed

- The shown-script elevation step now covers a capture on a process the run launched, not only an attach, including a named command that carries an elevation prefix; with no one present that capture is `blocked: capture needs elevation`.
- "Writing the Capture section" bars elevation prefixes (`sudo`, `doas`, `runas`) in a `## Capture` command and elevates only the recorder against a pid. The hang row names no capture kind yet (#9490).

## [0.2.0] - 2026-10-23

### Added

- `/app-control:drive` gains an attended-only `--attach`: it asks before each attach to a
  running process the person named, refuses under `--unattended` or with no person present and
  records the step as blocked, and runs any elevated attach only through a script it shows first.
- Four eval cases: ask before attaching, refuse with no one present, refuse under `--unattended`,
  and elevation through a shown script.

## [0.1.0] - 2026-10-21

### Added

- `drive` skill: launches and operates the project's app, observes it and records evidence, and
  never judges. Actions: bare drive, `ready`, `capture --kind <kind>` and `cleanup`, plus an
  `--unattended` mode that asks nothing and writes a fixed report a later job can read.
- It finds the project's `control-<app>` skill and falls back to the bundled `run` skill or a
  project-type recipe, and the report says which.
- `reference/control-skill.md` (the shape of a project's control skill), `reference/evidence.md`
  (the run directory, `report.md` and the `report.json` fields) and `reference/project-types.md`
  (the fallback recipes).
- Evals: four cases for the fallback line, a capability gap, a verdict-free report and an
  instruction found in app text.
