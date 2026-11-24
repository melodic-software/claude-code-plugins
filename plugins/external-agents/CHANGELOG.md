# Changelog

All notable changes to the `external-agents` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.2] - 2026-11-24

### Changed

- `external-agents update` reads a provider's config reference through the shared docs cache

  The page is read with the plugin's new `scripts/fetch-docs.sh --cache --profile generic` copy
  (with `docs-cache.sh`, `fetch-docs-generic.sh` and `html2md.py`, registered in
  `scripts/shared-copies.txt`), so a page another session read within the cache's TTL is served
from the cache instead of fetched again. A page the script leaves
  unread keeps the config keys unverified, naming its reason. `prerequisites.json` declares
  `curl` and `jq` as optional. The `fetch-docs-generic.sh` copy is not executable, like its
  canonical, because `fetch-docs.sh` sources it.

## [0.7.1] - 2026-11-24

### Fixed

- `external-agents models <product>` now prints `read_only_tools`, the tools that still work under
  `--mode read-only`, from a new `harness.read_only_tools` list in each provider record (Codex:
  `file`, `shell`, `web`, `mcp`; Antigravity: `file`). A record with no list reports `tools`
  there. Before this, `tools` was the only view, so a router could send a read-only research brief
  to Antigravity, whose read-only runs refuse shell, web and MCP calls.

## [0.7.0] - 2026-11-24

### Added

- add the `antigravity_uses_task_mode` userConfig option, so one per-user setting turns on
  Antigravity task writes in every repository and worktree

  It defaults to `read-only`, so nothing changes for a user who sets nothing. The command reads
  `pluginConfigs` from the user and managed settings itself and feeds the value to the config
  cascade's userConfig layer, which a repository's team or personal file still overrides. An
  unreadable settings file or managed-settings directory leaves the layer empty and prints a
  notice. The option's `options` picker needs Claude Code v2.1.271 or later.

## [0.6.2] - 2026-11-24

### Fixed

- When a CLI fact command fails, `external-agents update <product>` and `external-agents models <product>` add the start of what the CLI printed (stderr first, else stdout) to the reason, as in `models: models exited 1: <excerpt>`: one line, clipped to 200 characters, with email addresses replaced by `<email>`. A failed command that printed nothing keeps the old reason.
- The `antigravity` skill's update reference says what to do when `models.txt` is absent: relay the `models:` reason, and neither confirm nor reject a configured model slug.

## [0.6.1] - 2026-11-23

### Fixed

- The shared config resolver reads the personal override (`<home>/<plugin>.local.*`) from the repository's main checkout when it runs in a linked worktree that has no personal file of its own, so personal settings no longer drop in worktrees.
- The `binary_path` refusal for a personal file tracked by git checks the file the value was read from, so a value from the main checkout is checked in the main checkout.

## [0.6.0] - 2026-11-23

### Added

- `external-agents models <product>` now includes product-level `tools`, headless `image` capability, optional per-model `context_window` when the CLI reports it, and live `breaker` state (`open`, `reason`, `reset_at`) while keeping schema version 1.
- `external-agents usage <product>` reads current plan usage remaining as a normalized 0 to 1 fraction in a single JSON object outside delegated runs, driven by each provider record (`codex app-server` `account/rateLimits/read` for Codex; `agy --output-format json -p=/usage` without `--disable-slash-commands` for Antigravity) without printing account ids, emails or plan names.

## [0.5.0] - 2026-11-22

### Added

- `external-agents run <antigravity|codex>` takes a repeatable `--add-dir <absolute dir>` on a write run, mapped to each CLI's own `--add-dir` through its provider record, so a task can write a named directory outside its workspace. It is refused with exit 2 on a read-only run, a review, a resumed Codex thread, a relative path or a directory that does not exist. The job records `add_dirs` and `fence`, and `status <job>` prints both.
- `--unsandboxed auto` opts one antigravity write run into agy's `--mode auto`; on such a run the command reads agy's log for the run and, when it shows auto mode was applied, says so instead of reporting agy's auto-mode warning as a fallback. Codex declares no opt-in, so `--unsandboxed` is refused for it.

### Changed

- An antigravity write run is fenced by default: `--mode accept-edits` with agy's terminal sandbox on, sandboxed commands allowed and no access beyond the workspace, so a command that asks to leave the sandbox is refused and recorded `blocked-by-mode`. The `antigravity` and `codex` skills tell the delegating agent to decide every extra writable directory, and for agy whether an out-of-sandbox command is needed, before the run, and to name them in the prompt.

## [0.4.2] - 2026-11-22

### Fixed

- A signed-out agy run (`authentication failed or timed out`) or a `RESOURCE_EXHAUSTED` quota error now opens the antigravity breaker, so later runs skip with one notice until `external-agents update antigravity` or the cool-down, instead of each waiting out agy's 60-second sign-in prompt.

## [0.4.1] - 2026-11-22

### Changed

- The `antigravity` and `codex` skills leave the choice of vendor, model and effort for a task to `/multi-agent:route vendors <task>`; their `routing.md` files keep only each CLI's own facts and docs pointers.

## [0.4.0] - 2026-11-22

### Added

- `external-agents models <product>` prints the installed CLI's models and effort levels as one JSON document (schema 1), naming the command each fact came from, for other plugins such as `/multi-agent:route` to read instead of this plugin's cache files. It caches per CLI version and starts no model turn; a missing CLI is `unavailable` with exit 4.

### Changed

- `external-agents update codex` also caches `codex debug models`, and reports `check: cli facts` when it fails. The model list no longer joins the help text `update` searches for config keys.

## [0.3.0] - 2026-11-22

### Added

- `run` and `review` take `--effort <level>` to override `<product>.effort` for one run; agy receives `--effort` and Codex receives `-c model_reasoning_effort=<level>`. Each job records the model and effort it ran with, and `status <job>` prints them.

### Changed

- The `antigravity` and `codex` skills still pass no model or effort by default, so each vendor's shipped default runs; the calling agent may pass `--model` or `--effort` for one run when the user names one or a heavy whole-task delegation calls for it, and names the override in its reply.

## [0.2.2] - 2026-11-22

### Fixed

- The once-a-day CLI version check no longer deletes a lock another session has just created: when the lock it found disappears before its age is read, the shared `cli-version-check.mjs` retries instead of treating it as stale.

## [0.2.1] - 2026-11-22

### Fixed

- The once-a-day CLI version check no longer runs twice when two sessions start at the same moment: the shared `cli-version-check.mjs` now reads the clock after it takes its lock ([#18063](https://github.com/melodic-software/claude-code-plugins/issues/18063)).

## [0.2.0] - 2026-11-22

### Added

- Google Antigravity (`agy`) support: a provider record, the `antigravity` keys in `<home>/external-agents.yaml`, bundled defaults (every use read-only, council member on), and the agy prerequisite with its daily latest-release check. The `/external-agents:antigravity` skill drives the `external-agents` command for agy the way `/external-agents:codex` does for Codex. Read-only runs use agy's default approval mode through a per-run settings file, so writes and commands are refused and reported as blocked. Writes are opt-in through `antigravity.uses.task.mode: write`, because agy's auto mode, whose limit is agy's sandbox plus agy's own review, has no network isolation. With no `antigravity.model` set, agy's own default model runs. Every agy run passes `--disable-slash-commands`, so a prompt starting with `/` reaches the model as text, and a review warns when the branch changes agy's `.agents/` workspace configuration.

## [0.1.0] - 2026-11-22

### Added

- The `external-agents` plugin: hands tasks and reviews to other vendors' official coding-agent CLIs through their documented headless surfaces, Codex first. This release ships the `external-agents` command (`run`, `review`, `status`, `result`, `cancel`, and `update`, which reports a CLI's version, login and latest release, caches its help per version (from stderr when a CLI prints its help there, and reported when a help command prints nothing), and checks its docs index and the config keys the runner passes), the team config schema for `<home>/external-agents.yaml`, and the Codex prerequisite with its daily latest-release check. Every run passes the mode's sandbox and never an approval bypass; a briefed review names its merge base and changed files; a run whose commands the sandbox refused is recorded `blocked-by-mode`, not `ok`; a CLI that is missing, logged out or over its usage limit is refused until its next trial time; `cancel` and the run timeout stop the whole process tree. The `/external-agents:codex` skill drives the command: it runs a Codex task or investigation as a background job, resumes a thread, reviews a branch, and reads back `status`, `result`, `cancel` and `update`, with its first reply line naming the mode the job ran in, model and effort guidance as pointers to the Codex docs, and no model passed unless one is configured. It replaces OpenAI's `codex@openai-codex` plugin.
