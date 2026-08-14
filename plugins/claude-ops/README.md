# claude-ops

A Claude Code plugin for running Claude Code well over time — one cohesive
capability across ten skills and a family of telemetry-emitter hooks.
audit-install-state reports on the machine-scope `~/.claude` install directory
itself, audit-performance captures slowness evidence at the moment a machine or
session feels slow so the cause is diagnosed instead of nuked,
observability reads what your sessions actually did, known-issues tracks what
upstream has broken, changelog integration keeps your repo current with what
upstream has shipped, the plugins skill keeps your own plugin fleet current,
morning-brief prints your read-only operator morning view, lanes launches and
manages your loop lanes as background sessions, a
re-runnable `setup` action settles where the known-issues registry lives,
and the `*-audit` hooks feed observability with per-hook execution telemetry
Claude Code's native OTEL cannot see.

## Skills

| Skill | What it does |
|---|---|
| `/claude-ops:audit-install-state` | Read-only audit of the machine-scope Claude Code installation directory — the `~/.claude` tree plus the home-root `~/.claude.json`. Inventories every file (entries labelled as an authored surface or a rolled-up bulk tree, with the complete per-file rows in a CSV artifact), separates what Claude Code's own `cleanupPeriodDays` sweep already manages from what nothing manages, resolves what each number in a filename actually *is* before attempting any process-liveness lookup, and deny-lists any subtree holding a revert ledger before classifying anything as stale. Never deletes; hands off to `claude project purge` and `/disk-hygiene:clean`. |
| `/claude-ops:audit-performance` | Read-only slowness-diagnostic capture, run at the moment the machine or a session feels slow — before restarting or deleting anything. One timed engine pass separates the three documented suspects: accumulated install-tree state (retention-sweep health including the silent unparsable-`settings.json` pause, plus a timed stat-walk whose duration approximates the product's own daily sweep cost), version regression (CLI version against a bundled known-performance-issues reference), and component bloat (fleet and process censuses, verdict routed to `/claude-ops:plugins audit`). Phase timings are first-class evidence; content reads are allowlisted to `settings.json` and `.last-cleanup` — `~/.claude.json` and `history.jsonl` stay stat-only. Reports and routes; never mutates, never elevates. |
| `/claude-ops:observability` | Reads locally captured Claude Code telemetry — OTEL DuckDB store, machine-owned collector, optional Aspire dashboard, hook-event JSONL, ccusage — and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/claude-ops:known-issues` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/claude-ops:changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (impact triage, no edits), `status` (applied versions from git history), and `apply` (full explore → research → interview → implement pipeline, explicit user intent only). |
| `/claude-ops:plugins` | Brings a machine's plugin fleet current on demand: marketplace refresh, updates for the plugins that actually load (including in-repo project/local-scope installs), new-catalog-plugin install per policy, and scope-divergence detection. Actions: `sync` (default, CLI-mediated mutations only), `audit` (read-only dry run), `converge` (the one action that can touch a committed `.claude/settings.json` — previews and confirms per plugin first). |
| `/claude-ops:morning-brief` | Prints the read-only, `gh`-based operator morning view for the current repo in one pass: open counts per queue label (`priority: needs-triage`, `status: ready`, `status: needs-decision`, `needs-human`), the gh-native merge-ready PR list (non-draft + `mergeStateStatus=CLEAN`), parked `status: needs-decision` issues with their RECOMMENDED lines, and loop-lane telemetry freshness (per-lane `last-cycle` age + `flags:`). Never mutates anything; the authoritative PR merge gate stays `/source-control:babysit-prs`. |
| `/claude-ops:lanes` | Starts, restarts, stops, and reports loop lanes as named background Claude Code sessions seeded from canonical prompt files. `start` (default) / `restart` pull the repo and refresh the plugin marketplace, then launch each configured lane (`claude --bg -n <lane>`) with its per-lane `model`/`effort`; `status` shows per-lane running state and live sessionId; `stop` ends a lane via `claude stop`; `consume-restarts` is the OS-schedulable restart-request consumer — it reads each configured lane's telemetry `restart_request` and relaunches the stopped lanes that asked, through the same launcher (#1653). Acts only on sessions whose name is a configured lane. Lanes come from a JSON config (`--config`, else `$CLAUDE_OPS_LANES_CONFIG`, else `<repo>/.work/lanes.json`); prompt storage is session-local `.work` today and composes with #480 for a durable home. |
| `/claude-ops:setup` | `check` (default) reports the effective known-issues-registry and skill-usage-log destinations, their defaults, and path containment; `apply` routes personal option changes through Claude Code's plugin configuration prompt. |

## The audit hooks

Eight advisory `*-audit` hooks (across nine hook scripts —
`skill-usage-audit` has two producers, see below) emit the marketplace
[hook-telemetry envelope](../../docs/conventions/hook-telemetry/README.md) — one
JSON event per run carrying that hook's own `duration_ms`, outcome, and a
privacy-safe subject. Each is independently toggleable via its own `userConfig`
boolean (default **on**; see [Per-hook kill switches](#per-hook-kill-switches)).
The six pure emitters are a no-op until a consumer wires a sink (below);
`skill-usage-audit` is one exception — both its producers also write the shared
`skill-usage.jsonl` second store unconditionally (disable the whole feature with
`skill_usage_audit_enabled=false`; pick the store's home with `skill_usage_scope`
and `skill_usage_dir`). In the default repo scope the store dir is kept out of
`git status` via an idempotent machine-local `.git/info/exclude` entry
(`skill_usage_git_exclude=false` opts out for teams that commit the telemetry).
`hook-failure-audit` is the other exception — its user-facing `systemMessage`
warning fires regardless of sink wiring (only its envelope needs a sink),
because its whole subject is failures nothing else surfaces: a hook that fails
to launch is a non-blocking error, the guarded tool call proceeds as if
approved, and the only durable trace is a transcript attachment no human reads
(#2577). It runs once per `Stop`, tails a bounded window of the session
transcript for `hook_non_blocking_error` attachments (structural match on the
attachment type — never substring), and warns once per session per distinct
failing hook, re-warning when a new hook starts failing. It lives in this
plugin, not in the plugin it might report on, deliberately: an in-plugin
detector shares its plugin's registration form and dies with it, which is
exactly how disk-hygiene's guard monitor missed the #1416 incident class.

`skill-usage-audit` is captured by two disjoint producers so both invocation
paths are measured: the model-invoked `Skill` tool (`PostToolUse`) and the
user-typed slash command (`UserPromptExpansion`, which bypasses the `Skill`
tool). Events carry a `source` field (`tool` vs `expansion`) so consumers can
tell the paths apart; both share the same telemetry `hook` id and second store.

| Hook | Event | Emits |
|---|---|---|
| `api-error-audit` | StopFailure | API turn-failure `error_type` (never the message body) |
| `config-change-audit` | ConfigChange | the mutated `config_source` |
| `instructions-loaded-audit` | InstructionsLoaded | `<repo-relative-file>:<load_reason>` (absolute prefix stripped; session_start filtered by default) |
| `permission-denied-audit` | PermissionDenied | classifier denials, `Bash:<first-token>` subject |
| `pre-compact-audit` | PreCompact | compaction `trigger` (`manual`/`auto`) |
| `skill-usage-audit` (tool path) | PostToolUse (`Skill`) | model-invoked skill; `source: "tool"`; also writes the `skill-usage.jsonl` second store |
| `skill-usage-audit` (expansion path) | UserPromptExpansion | user-typed `/command` (`slash_command`/`mcp_prompt`); `source: "expansion"` + `expansion_type`; same second store |
| `tool-failure-audit` | PostToolUseFailure | Write/Edit/Bash failures, privacy-safe subject |
| `hook-failure-audit` | Stop | unsurfaced `hook_non_blocking_error` attachments; envelope subjects are hook names only; also warns via `systemMessage` |

None captures a command body, absolute path, error message, or argument body —
only category labels, privacy-safe subjects, and (for `instructions-loaded-audit`)
the repo-relative path of the loaded rule file.

### Per-hook kill switches

Each audit hook is toggled by its own `userConfig` boolean (default **on**; set
to `false` for a clean no-op) — disable one hook without touching the others.
The hooks read them through the native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process
mirror.

| Hook | Option |
|---|---|
| `api-error-audit` | `api_error_audit_enabled` |
| `config-change-audit` | `config_change_audit_enabled` |
| `instructions-loaded-audit` | `instructions_loaded_audit_enabled` |
| `permission-denied-audit` | `permission_denied_audit_enabled` |
| `pre-compact-audit` | `pre_compact_audit_enabled` |
| `skill-usage-audit` (both paths) | `skill_usage_audit_enabled` |
| `tool-failure-audit` | `tool_failure_audit_enabled` |
| `hook-failure-audit` | `hook_failure_audit_enabled` |

`instructions-loaded-audit` drops deterministic, high-volume `session_start`
loads by default; set `instructions_loaded_audit_log_session_start=true` to opt
back into logging them. A `stdin_read_timeout` option (seconds, default `2`) is
an **idle** bound on reading each hook's payload: any byte arriving resets it, so
a large or slowly-delivered payload is never cut off while it is still coming,
and it fires only once the pipe has gone silent for that long — at which point
these audit hooks fail open (skip). On a shell whose `read -t` accepts fractional
values the bound is read in four slices, so the stall is detected within a
quarter of the configured interval of it; where fractional timeouts are
unavailable (Bash 3.2, the macOS system shell) it is read as one window and a
producer that sends bytes then goes silent can take up to two intervals. A producer
that keeps emitting is bounded by Claude Code's own hook timeout, not by this
value. A setting this shell's `read -t` will not accept — or `0` — falls back to
the default.

Set them interactively with `/plugin configure claude-ops@<marketplace>`, or headless on the
install command:

```shell
claude plugin install claude-ops@<marketplace> --config skill_usage_audit_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To turn a hook off for a single repository, disable the whole plugin
in that project's `enabledPlugins` instead.

### Wiring the reference sink

A migrated emitter is inert without a consumer. `hooks/hook-telemetry-sink.sh`
is a **reference** sink: it reads an envelope on stdin and appends one line to
`<project-root>/.claude/observability/hook-events.jsonl` — exactly the shape the
`observability` skill reads.

Wire it by pointing `HOOK_TELEMETRY_SINK` at an **executable that exists at
resolution time**. A *relative* value resolves against the **consuming repo
root**, not the plugin cache — so the marketplace-installed copy under
`${CLAUDE_PLUGIN_ROOT}` is **not** reachable by a relative path (and Claude Code
injects `settings.json` `env` values literally, with no `${CLAUDE_PLUGIN_ROOT}`
expansion). Two workable forms:

- **Copy the reference sink into your repo** (e.g. `.claude/hooks/hook-telemetry-sink.sh`)
  and wire that repo-relative path — the portable, team-shared, clone-safe form:

  ```json
  { "env": { "HOOK_TELEMETRY_SINK": ".claude/hooks/hook-telemetry-sink.sh" } }
  ```

  The sink `source`s `hook-utils.sh` from its own directory, so a bare copy
  fails at startup: either copy `hook-utils.sh` alongside it, or edit the copy's
  `source` line to point at a `hook-utils.sh` your repo already carries.

- **Or** point at an **absolute** path to the installed sink under your plugin
  cache — per-machine, and it moves on each plugin update, so it is not
  clone-portable.

Any envelope producer (this plugin's hooks, guardrails, the formatters) then
flows into the same store. The sink is fire-and-forget and best-effort — a slow
or absent sink silently drops the event; it is for observability, not
audit-of-record.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install claude-ops@<marketplace>
```

## How the skills adapt to your repo

The defaults are repo-agnostic and everything project-specific routes through
your own repository's context:

- **Observability data locations.** The OTEL store defaults to
  `<project-root>/.claude/observability/otel` and is overridable via the
  `CC_OTEL_STORE` env var (retention windows via `CC_OTEL_RETENTION_DAYS` /
  `CC_OTEL_BODY_RETENTION_DAYS`). The hook-event JSONL source is read from
  `<project-root>/.claude/observability/hook-events.jsonl` only when your own
  hooks emit it; every source degrades gracefully when absent.
- **Persistent state** defaults to the plugin's own per-machine data directory
  (`${CLAUDE_PLUGIN_DATA}`): the known-issues registry
  (`registry.json`), `check-all` output, `--write` observability reports, and
  the `lanes` skill's per-lane launch-commit markers
  (`${CLAUDE_PLUGIN_DATA}/lanes/<repo-key>/<lane>-launch-commit`, overridable
  via `lane-launcher.sh --data-dir`). `<repo-key>` namespaces markers by
  repository — the data directory is plugin-wide, while a lane name like `work`
  is only unique within one checkout. It is a digest of the repository's
  canonical path; print the one for a given checkout with
  `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`. By default nothing is written into your
  repository. Opt in for the registry via the `registry_dir` option (see
  Configuration) to keep it git-tracked and team-shared inside your repo
  instead.
- **Work-item and docs integration.** Where the skills propose follow-up work
  items or cross-reference quirks/workaround docs, they use whatever tracker
  and docs your project has (e.g. `gh issue create`, your `CLAUDE.md` /
  `.claude/rules`) and skip silently when there is none.

## Requirements

The audit hooks are Bash scripts (Git Bash on native Windows — install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)) and
use `jq`; without jq they fail open (no audit line is written).

`audit-install-state` needs **Python 3.11+ only** — no PowerShell, no third-party packages, no
`jq`. Its inventory, surface classification, filename-scheme resolution, retention resolution and
sampling are pure `os.walk` + `stat` + regex and behave identically on every platform. The single
OS-specific seam is one function, `probe_pid()`, with a POSIX body (`os.kill(pid, 0)`) and a Windows
body (`OpenProcess`); a probe that cannot run reports `unverified`, never `dead`.

Core flows need only `git`, `jq`, `gh` (authenticated), and `python3`.
Optional: `duckdb` for OTEL store queries and `npx` for ccusage. The machine-level
`otelcol-contrib` service and Aspire dashboard Compose stack are provisioned separately; the
plugin observes them but does not start them. Every skill reports missing optional tooling
instead of failing.

## Configuration

The per-hook kill switches, `instructions_loaded_audit_log_session_start`, and
`stdin_read_timeout` are documented under
[Per-hook kill switches](#per-hook-kill-switches). Three further `userConfig`
options tune the skills:

- **`install_new`** (string, optional) — new-catalog-plugin install policy for the `plugins`
  skill's `sync` action. `ask` (default) offers not-yet-installed catalog plugins in one batched
  multi-select prompt; `all` installs every one automatically; `none` reports them without
  installing. The manifest schema has no `enum` type, so this validates in prose, not JSON Schema;
  any other value is treated as `ask`.
- **`registry_dir`** (string, optional) — project-relative directory for the
  known-issues registry (`registry.json`). Set it to keep the
  registry inside your repo (git-tracked, team-shared) instead of the
  per-machine plugin data directory; leave unset to use `${CLAUDE_PLUGIN_DATA}`.
  Absolute, drive-qualified, UNC, traversal, and escaping-symlink paths are
  invalid; known-issues operations must stop and direct you to reconfigure
  rather than write outside the project.
- **`skill_usage_scope`** (string, optional) — where the `skill-usage-audit`
  second store lives. `repo` (default) keeps it in the project tree, with a
  machine-local `.git/info/exclude` entry so `git status` stays clean; `user`
  resolves the same `skill_usage_dir` subpath under `$HOME` for one cross-repo
  operator store (rows carry `project` + collision-resistant `project_id`
  fields); `data-dir` writes
  `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>` — plugin-owned, update-safe,
  never in any repo tree. Prose-validated (no `enum` in the manifest schema);
  an unknown value falls back to `repo` with a one-time advisory. The default
  stays `repo` deliberately: the store sits beside `hook-events.jsonl`, matching
  the observability posture that telemetry is project-local, and the exclude
  entry removes the status noise that motivated the scope knob.
- **`skill_usage_git_exclude`** (boolean, default `true`) — repo scope only:
  idempotently exclude the store dir via `.git/info/exclude` (never touches
  `.gitignore` or tracked files). Set `false` when your team deliberately
  commits the telemetry.
- **`skill_usage_dir`** (string, optional) — contained relative directory,
  resolved under the scope root (repo scope: repo root; user scope: `$HOME`),
  where `skill-usage-audit` writes its `skill-usage.jsonl` second store (the
  "measuring skills" record, separate from the telemetry envelope); leave unset
  to use `.claude/observability`. The same containment rules apply in every
  scope; the `data-dir` scope ignores it. An invalid
  value produces a visible advisory and skips the second-store write; telemetry
  through an independently configured sink can still proceed.

Run `/claude-ops:setup` to validate this choice. Claude Code owns persistence through its plugin
configuration prompt; rerun setup afterward to verify the rendered value.

Remaining variability is covered by the env vars above and conventional
project-relative defaults; the bundled scripts make no outbound network calls
except `gh`/`curl` reads of GitHub and Claude status pages in the
known-issues skill.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `registry_dir` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_REGISTRY_DIR` | Optional contained project-relative directory holding the known-issues registry (registry.json). Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. Leave unset to use ${CLAUDE_PLUGIN_DATA}. |
| `skill_usage_dir` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR` | Optional contained relative directory where the skill-usage-audit hooks write skill-usage.jsonl, resolved under the skill_usage_scope root (repo scope: the project root; user scope: $HOME). Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid in every scope. Ignored by the data-dir scope (plugin-owned layout). Leave unset to use .claude/observability. |
| `skill_usage_scope` | string | `"repo"` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE` | Where the skill-usage store lives. Valid values: "repo" (default — project tree under the repo root, kept out of git status via a machine-local .git/info/exclude entry), "user" (the skill_usage_dir subpath under $HOME, one cross-repo store; rows carry a project field), "data-dir" (${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>, plugin-owned and update-safe). The manifest schema has no enum type, so this validates in prose; any other value is treated as "repo" with a one-time advisory. |
| `skill_usage_git_exclude` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE` | When the repo-scope store sits inside a git work tree, idempotently add its directory to .git/info/exclude (machine-local; never touches .gitignore or tracked files) so git status stays clean. Set false if your team deliberately commits the telemetry. |
| `install_new` | string | `"ask"` | `CLAUDE_PLUGIN_OPTION_INSTALL_NEW` | Controls what `sync` does with catalog plugins that aren't installed yet. Valid values: "ask" (default — offer them in one batched multi-select prompt), "all" (install every one automatically), "none" (report only, never install). The manifest schema has no enum type, so this validates in prose, not JSON Schema; any other value is treated as "ask". |
| `api_error_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_API_ERROR_AUDIT_ENABLED` | Emit turn-failure telemetry on API errors |
| `config_change_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONFIG_CHANGE_AUDIT_ENABLED` | Emit telemetry on config-source mutations |
| `instructions_loaded_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_ENABLED` | Emit telemetry on rule/instruction file loads |
| `permission_denied_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PERMISSION_DENIED_AUDIT_ENABLED` | Emit telemetry on permission denials |
| `pre_compact_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PRE_COMPACT_AUDIT_ENABLED` | Emit telemetry on context-compaction events |
| `skill_usage_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED` | Emit telemetry on skill usage; shared by both skill-usage audit hooks (the Skill-tool and slash-command expansion paths) and also gates the shared skill-usage.jsonl store |
| `tool_failure_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_TOOL_FAILURE_AUDIT_ENABLED` | Emit telemetry on Write/Edit/Bash tool failures |
| `instructions_loaded_audit_log_session_start` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START` | Opt back into logging session_start instruction loads (dropped by default as deterministic and high-volume) |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin — how long the pipe may go silent before the hook gives up and fails open |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure claude-ops@<marketplace>`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install claude-ops@<marketplace> --config registry_dir=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "claude-ops@<marketplace>": {
         "options": {
           "registry_dir": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
