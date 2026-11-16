# session-telemetry

Collects telemetry about each Claude Code session (hook runs, session events and skill use) from this
plugin's hooks and from any plugin's hook-telemetry producers, for later analysis. It is hooks only:
no skills. It is off by default; turn it on with

```shell
claude plugin enable session-telemetry@<marketplace>
```

and start a new session. Where its records live, for a reader in another plugin, is the
[session telemetry data contract](../../docs/contracts/session-telemetry-data/README.md);
`/harness-ops:observability`, `/harness-ops:audit-skill-visibility` and `/harness-ops:setup` read
them when harness-ops is enabled.

## Contents

- [The audit hooks](#the-audit-hooks)
- [Install](#install)
- [Requirements](#requirements)
- [Configuration](#configuration)

## The audit hooks

Seven advisory `*-audit` hooks, registered as eight rows because
`skill-usage-audit` has two producers, emit the marketplace
[hook-telemetry envelope](../../docs/contracts/hook-telemetry/README.md). One
JSON event per run carrying that hook's own `duration_ms`, outcome, and a
privacy-safe subject. Each is independently toggleable via its own `userConfig`
boolean (default **on**; see [Per-hook kill switches](#per-hook-kill-switches)).

Two scripts serve those eight rows. `hooks/audit-event-emitter.sh` carries
seven of them and picks the row from the payload's `hook_event_name`, the way
`session-event-log.sh` next to it serves 28 events from one file; the
seven events are distinct, so the event alone selects the row. Each row still
reads its own `<name>_enabled` switch and emits the same telemetry `hook` id,
`hook_event`, `status` and `data` fields it emitted as a standalone script, so
no downstream reader can tell the difference. The row with earned behavior
of its own keeps its file: `skill-usage-audit.sh`, whose kill switch is
inlined above its library `source` because it sits on the hot `PostToolUse`
path.

The [hook budget](../../docs/contracts/hook-budget/README.md) is accounted per
`hooks.json` entry, and the collapse changes no entry: the same eight audit rows,
on the same events, with the same matchers, and one event still spawns exactly
one process. Per-entry cost is unchanged for an enabled row (the same library,
the same `jq` passes, plus one bash pattern match to read the event) and lower
when every switch is off, because the emitter reads all seven switches before it
parses the library. A row that is off on its own pays one buffered payload it
did not pay before, because the row is only known once the event has been read;
it parsed the same library then as now, and no extra process runs either way.

The six pure emitter rows are a no-op until a consumer wires a sink (below);
`skill-usage-audit` is one exception. Both its producers also write the shared
`skill-usage.jsonl` second store unconditionally (disable the whole feature with
`skill_usage_audit_enabled=false`; pick the store's home with `skill_usage_scope`
and `skill_usage_dir`). In the default repo scope the store dir is kept out of
`git status` via an idempotent machine-local `.git/info/exclude` entry
(`skill_usage_git_exclude=false` opts out for teams that commit the telemetry).

One row per Skill call, with these fields:

| Field | Present | What it holds |
|---|---|---|
| `ts` | always | UTC timestamp of the call, `YYYY-MM-DDTHH:MM:SSZ` |
| `event` | always | `SkillUse`, the key readers filter this store on |
| `skill` | always | the skill name, leading slash stripped |
| `branch` | always | the checked-out branch, `unknown` outside a git work tree |
| `project` | always | the project root's basename, for display |
| `project_id` | always | basename plus a digest, collision-resistant across checkouts in the user and data-dir scopes |
| `hook` | always | `skill-usage-audit` |
| `source` | always | `tool` (the Skill tool) or `expansion` (a user-typed slash command) |
| `expansion_type` | expansion path only | `slash_command` or `mcp_prompt` |

`skill-usage-audit` is captured by two disjoint producers so both invocation
paths are measured: the model-invoked `Skill` tool (`PostToolUse`) and the
user-typed slash command (`UserPromptExpansion`, which bypasses the `Skill`
tool). Events carry a `source` field (`tool` vs `expansion`) so consumers can
tell the paths apart; both share the same telemetry `hook` id and second store.

Its share of the budget is stated as a **git process count**, the part of the
row's cost that varies with the store's contents. The store write spawns
**3 git processes**: the repo-root read, the `.git/info/exclude` hygiene read
(repo scope only), and one `git rev-parse --abbrev-ref HEAD` for the branch.
Measured with `strace -ff -e trace=execve` on a throwaway fixture repository. This row is not in
the always-on per-tool-call set: its matcher is `Skill`, so an ordinary tool
call spawns nothing.

| Hook | Event | Emits | Why it earns its spawn |
|---|---|---|---|
| `api-error-audit` | StopFailure | API turn-failure `error_type` (never the message body) | The event only fires when a turn fails at the API, so the hook costs nothing on a healthy session |
| `config-change-audit` | ConfigChange | the mutated `config_source` | Matcher-scoped to the four sources that can change behavior, and a settings or skills change is rare |
| `instructions-loaded-audit` | InstructionsLoaded | `<repo-relative-file>:<load_reason>` (absolute prefix stripped; session_start filtered by default) | The highest-volume row here, and the only one whose cost is worth watching. It is advisory: InstructionsLoaded ignores the exit code, so the hook never gates a load, and the session_start write-time filter keeps the noisiest reason out of the store by default |
| `permission-denied-audit` | PermissionDenied | classifier denials, `Bash:<first-token>` subject | Fires only on an actual denial, and it is the only durable record of what the classifier refused |
| `pre-compact-audit` | PreCompact | compaction `trigger` (`manual`/`auto`) | Once per compaction, which is the rarest event this plugin observes |
| `skill-usage-audit` (tool path) | PostToolUse (`Skill`) | model-invoked skill; `source: "tool"`; also writes the `skill-usage.jsonl` second store | Matcher-scoped to `Skill`, so it is skipped on every other tool call rather than firing per PostToolUse |
| `skill-usage-audit` (expansion path) | UserPromptExpansion | user-typed `/command` (`slash_command`/`mcp_prompt`); `source: "expansion"` + `expansion_type`; same second store | Fires per expanded slash command, not per prompt, and it is the only path that sees a user-typed invocation (the `Skill` tool never runs) |
| `tool-failure-audit` | PostToolUseFailure | Write/Edit/Bash failures, privacy-safe subject | Matcher-scoped to the three tools whose failures are actionable, and the event fires only on failure |

None captures a command body, absolute path, error message, or argument body, only category labels, privacy-safe subjects, and (for `instructions-loaded-audit`)
the repo-relative path of the loaded rule file.

The InstructionsLoaded row carries no matcher on purpose. That event's matcher selects on load
reason, and the row passes every reason through verbatim into its subject, so
scoping to the full documented set would skip nothing and would silently drop any reason a later
release adds. Scoping below that set is worse: the only reason worth excluding for cost is
`session_start`, which the row already drops at write time, and it drops it behind the
`instructions_loaded_audit_log_session_start` option. A matcher that excluded `session_start` would
stop the hook from ever spawning on it, leaving that option switched on but unable to log anything.
The row therefore stays unscoped until the option is retired.

### Per-hook kill switches

Each audit hook is toggled by its own `userConfig` boolean (default **on**; set
to `false` for a clean no-op). Disable one hook without touching the others.
The hooks read them through the native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process
mirror. Seven rows share `audit-event-emitter.sh`, which reads the switch of the
row the event selected: sharing a script does not share a switch, and turning one
row off leaves the other six emitting.

| Hook | Option |
|---|---|
| `api-error-audit` | `api_error_audit_enabled` |
| `config-change-audit` | `config_change_audit_enabled` |
| `instructions-loaded-audit` | `instructions_loaded_audit_enabled` |
| `permission-denied-audit` | `permission_denied_audit_enabled` |
| `pre-compact-audit` | `pre_compact_audit_enabled` |
| `skill-usage-audit` (both paths) | `skill_usage_audit_enabled` |
| `tool-failure-audit` | `tool_failure_audit_enabled` |

`instructions-loaded-audit` drops deterministic, high-volume `session_start`
loads by default; set `instructions_loaded_audit_log_session_start=true` to opt
back into logging them. A `stdin_read_timeout` option (seconds, default `2`) is
an **idle** bound on reading each hook's payload: any byte arriving resets it, so
a large or slowly-delivered payload is never cut off while it is still coming,
and it fires only once the pipe has gone silent for that long, at which point
these audit hooks fail open (skip). On a shell whose `read -t` accepts fractional
values the bound is read in four slices, so the stall is detected within a
quarter of the configured interval of it; where fractional timeouts are
unavailable (Bash 3.2, the macOS system shell) it is read as one window and a
producer that sends bytes then goes silent can take up to two intervals. A producer
that keeps emitting is bounded by Claude Code's own hook timeout, not by this
value. A setting this shell's `read -t` will not accept, or `0`, falls back to
the default.

Set them interactively with `/plugin configure session-telemetry@<marketplace>`, or headless on the
install command:

```shell
claude plugin install session-telemetry@<marketplace> --config skill_usage_audit_enabled=false
```

Option scoping (user vs project settings, and the per-repository escape hatch)
per "How to set these" below.

### Wiring the reference sink

A migrated emitter is inert without a consumer. `hooks/hook-telemetry-sink.sh`
is a **reference** sink: it reads an envelope on stdin and appends one line under
the hook log root, `<project-root>/.observability/claude` by default (the
`session_event_log_dir` option moves it). An envelope carrying
`data.session_id` lands in `sessions/<session_id>.jsonl`, beside the
per-session event log; one without lands in the shared `hook-events.jsonl`
in the legacy shape; that file rotates to `hook-events.jsonl.1` at
`hook_events_max_bytes` whatever the session-log switch is set to. Both are
what harness-ops' `observability` skill reads. The root carries a self-ignoring
`.gitignore`, created on the first write (or by `/harness-ops:setup apply` when
harness-ops is enabled).

Wire it with the reserved value `@session-telemetry`, committed in the repository's
`settings.json`. No copy of the sink goes in the repository and no per-machine
path goes in the settings:

```json
{ "env": { "HOOK_TELEMETRY_SINK": "@session-telemetry" } }
```

At each session start this plugin rewrites, only when it changed, a launcher in
its plugin data directory, `~/.claude/plugins/data/session-telemetry-<marketplace>/hook-telemetry-sink.sh`
(under `CLAUDE_CONFIG_DIR` when that is set). The data directory survives plugin
updates; the installed sink under `${CLAUDE_PLUGIN_ROOT}` moves on each one, and
Claude Code copies `settings.json` `env` values as written, with no
`${CLAUDE_PLUGIN_ROOT}` expansion. Every producer resolves `@session-telemetry` to that
launcher (`docs/contracts/hook-telemetry` at the repository root, "Sink path
resolution"), which runs the installed sink with this plugin's
`session_event_log_dir` and `hook_events_max_bytes`, so rows from every producer
land in the same root. Until the first session start writes the launcher, and on
a machine without this plugin, producers skip the event.

Two other forms remain, for a sink of your own or a pinned copy:

- **A repository copy**, wired by a repo-relative path such as
  `.claude/hooks/hook-telemetry-sink.sh` (a relative value resolves against the
  consuming repository's root). The sink sources two files from its own
  directory, so copy all three side by side:
  `hooks/hook-telemetry-sink.sh`, `hooks/hook-utils.sh` (for
  `hook::repo_root_to`) and `hooks/session-log-lib.sh` (the record formatter
  and root guard). A copy does not follow plugin updates.
- **An absolute path** to the installed sink under your plugin cache. It is
  per-machine and moves on each plugin update.

Any envelope producer (this plugin's hooks, guardrails, the formatters) then
flows into the same store. The sink is fire-and-forget and best-effort, a slow
or absent sink silently drops the event; it is for observability, not
audit-of-record.

### The per-session hook event log (off by default)

Independently of any sink, `session_event_log_enabled=true` turns on the log.
It is a mod: the hooks module `hooks/register.ts` hooks one `classic.<Event>`
per observable hook event (28 events; the generated
`hooks/hook-events.registry.json` says which, and why `WorktreeCreate`,
`MessageDisplay` and `FileChanged` are left out), only while the switch is on,
and only for the categories `session_event_log_categories` enables (see below).
`PreToolUse` and `PostToolUse` are left out too: they fire on every tool
call, so an enabled log would cost a process creation per call. Tool activity
is still recorded through `PostToolUseFailure` and `PostToolBatch`. A batch is
one line, not a per-call record: it carries the first `tool_name` and
`tool_use_id` the payload text holds, normally the first call's. Each fire
appends one line to `<root>/sessions/<session_id>.jsonl`: the correlation keys
the payload carries (`prompt_id`, `tool_use_id`, `agent_id`), the event and its
category, the tool and a repo-relative file path when present.

Process cost: with the switch off (the default) the module hooks nothing, so no
event starts a process (k = 0; `hooks/session-event-log.test.ts` counts the
processes for every event). On, a mod cannot append to a file, so each event
in an enabled category starts one process: the module hands the event's payload to
`hooks/session-event-log.sh` through `node hooks/exec-bash.mjs`, the same script
and launcher the settings rows ran. `SessionEnd` also starts one for retention,
and records its own line only when `session` is enabled. No event waits on the
write, which runs on a timer after the event goes on; `SessionEnd` waits for its
scripts, inside its teardown budget. Enabled, a 2 KB payload costs about 5 ms and a 512 KB one 36 ms of
script time on the Linux CI host. The parallel wall, the 4 KB and 16 KB appends,
`ls -t`, and the late-EOF stall are measured by
[`hooks/measure-hook-log-budget.sh`](hooks/measure-hook-log-budget.sh) and
recorded in
[`reference/hook-log-budget.md`](reference/hook-log-budget.md). On Windows Git
Bash (2026-09-30), thirty parallel events take 466 ms wall on, and the 4 KB and
16 KB appends leave 0 corrupt lines out of 33. `ls -t` ties at one-second
resolution there, so no ordering is claimed. The switch stays off by default.

The module needs Claude Code 2.1.287 or later with mods on. Its registration
by category was tested with `claude plugin test` on Claude Code 2.1.326, and no
older build is claimed for it; no live session type was run. Where
mods are off (below 2.1.287, under `disableAllHooks`, with `--bare`, or when
mods are switched off), the log does not run: no session file is written and
retention does not prune.

The built-in guard `sec-default` loads on a machine with managed settings or a
`managed-mcp.json`, and for a session on a Team or Enterprise `/login`. There
it holds each `classic.*` hook the module registers, so the log does not run.
Claude Code reports the held hooks in a `/plugin` note and, from 2.1.304, in a
line per skipped event. Registering only the chosen categories limits the
per-event lines to the events you chose; no change to the `/plugin` note is
claimed. No user setting or mod signal turns the guard
off. The log runs there only after an administrator installs session-telemetry
as one of the organization's mods, or leaves `sec-default@builtin` out of
managed `prependPlugins`, which removes the whole guard: see
[Install your organization's mods](https://code.claude.com/docs/en/plugins/mods/admin#install-your-organizations-mods)
and
[Know which hooks of a user's mod don't run](https://code.claude.com/docs/en/plugins/mods/admin#hooks-the-guard-passes-over).
Otherwise leave the switch off on that machine. Mods start
processes in the CLI only; where `$.process.run` cannot run, the module writes
nothing and logs that once to the debug log. A row's `traceparent` key is not
written, since a mod receives no per-hook `TRACEPARENT`. These differences from
the settings rows the log replaced are recorded in
[ADR 0065](../../docs/adr/0065-move-the-harness-ops-session-event-log-into-a-mod.md).

`session_event_log_categories` narrows the set, and registration follows it:
an event in an unlisted category is not hooked and starts no process. A changed
list applies at the next start. `SessionEnd` is hooked whenever the switch is
on, for retention, and records its line only when `session` is listed. At
`SessionEnd` the retention script, gated by the same switch, keeps the newest
`session_log_keep_sessions` or the last `session_log_keep_days` days, and
`session_log_pre_prune_command` hands an archiver the files about to go. The
root carries its own `*` `.gitignore`, so nothing under it reaches
`git status`. When harness-ops is enabled, `/harness-ops:setup` reports the toggles and the log root's `.gitignore` guard,
and `/harness-ops:observability session` reads the result.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install session-telemetry@melodic-software
```

## Requirements

The audit hooks are Bash scripts (Git Bash on native Windows, so install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)) and
use `jq`; without jq they fail open (no audit line is written).

**Node.js on PATH.** Every hook row starts through `node hooks/exec-bash.mjs`, which finds the real
Bash and runs the script. Claude Code's native binary neither ships nor uses Node.js
([setup](https://code.claude.com/docs/en/setup)), so without `node` on PATH the hooks do not launch;
plugin-diagnostics, when enabled, reports a missing `node`.
`node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether `node` and `jq`
resolve.

**Mods for the session event log.** The per-session hook event log runs in the hooks module, so it
needs Claude Code 2.1.287 or later with mods on; where mods are off it does not run (see
[The per-session hook event log](#the-per-session-hook-event-log-off-by-default)). The audit rows
are settings hooks and run with mods off.

## Configuration

The per-hook kill switches, `instructions_loaded_audit_log_session_start` and `stdin_read_timeout`
are documented under [Per-hook kill switches](#per-hook-kill-switches). These options place and cap
the skill-usage store:

- **`skill_usage_scope`** (string, optional), where the `skill-usage-audit`
  second store lives. `repo` (default) keeps it in the project tree, with a
  machine-local `.git/info/exclude` entry so `git status` stays clean; `user`
  resolves the same `skill_usage_dir` subpath under `$HOME` for one cross-repo
  operator store (rows carry `project` + collision-resistant `project_id`
  fields); `data-dir` writes
  `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>`. Owned by this plugin, update-safe,
  never in any repo tree. `/config` shows the three values as a picker; a value
  set by hand outside it falls back to `repo` with a one-time advisory. The default
  stays `repo` on purpose. The store stays in the project tree, matching
  the observability posture that telemetry is project-local, and the exclude entry removes the status noise that
  motivated the scope knob. (The hook log
  root is a separate tree with its own self-ignoring guard; see "Wiring the
  reference sink".)
- **`skill_usage_git_exclude`** (boolean, default `true`). Repo scope only:
  idempotently exclude the store dir via `.git/info/exclude` (never touches
  `.gitignore` or tracked files). Set `false` when your team deliberately
  commits the telemetry.
- **`skill_usage_dir`** (string, optional). Contained relative directory,
  resolved under the scope root (repo scope: repo root; user scope: `$HOME`),
  where `skill-usage-audit` writes its `skill-usage.jsonl` second store (the
  "measuring skills" record, separate from the telemetry envelope); leave unset
  to use `.claude/observability`. The same containment rules apply in every
  scope; the `data-dir` scope ignores it. An invalid
  value produces a visible advisory and skips the second-store write; telemetry
  through an independently configured sink can still proceed.
- **`skill_usage_max_bytes`** (number, default `10485760`). Size at which a producer moves
  `skill-usage.jsonl` to `skill-usage.jsonl.1`, replacing any older `.1`, before it appends, the
  rule `hook-events.jsonl` follows.

### Option details

**`session_event_log_enabled`.** Off, the hooks module hooks no event, so the log starts no process.
On, each event in an enabled category starts one process, and `SessionEnd` always starts retention.
The log runs only where mods load.

**`session_event_log_dir`.** Inside a checkout the directory carries a self-ignoring `.gitignore`,
created on the first write. In a linked worktree the path is relative to the main checkout, not the
worktree. The hooks write there and `/harness-ops:observability` (when harness-ops is enabled) reads there, so a worktree
session's logs stay after the worktree is removed.

**`hook_events_max_bytes`.** Read only when a session-telemetry hook emits the envelope: an emitter in
another plugin that runs the sink keeps the 10485760 default. A value above 999999999999999999 is
ignored and the default applies.

**`session_log_pre_prune_command`.** The session files about to be pruned are moved into the
directory passed as the argument, and its physical delete waits for the next retention run after
24 hours, so an archiver has a stable set to read. The command runs through `bash -c`, so it is
trusted configuration: on current releases project and local `pluginConfigs` are ignored and only
the user's own settings supply it (recheck: the plugins reference's user-configuration section).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `skill_usage_audit_enabled` | boolean | `true` | Emits telemetry on skill usage, on by default. Shared by both skill-usage audit hooks (the Skill-tool and slash-command expansion paths), and also gates the shared skill-usage.jsonl store. |
| `skill_usage_scope` | string | `"repo"` | Where the skill-usage store lives. repo (default) keeps it in the project tree, out of git status via a machine-local .git/info/exclude entry; user puts the skill_usage_dir subpath under $HOME as one cross-repo store; data-dir uses ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>. |
| `skill_usage_dir` | string | *(none)* | Relative directory where the skill-usage-audit hooks write skill-usage.jsonl, under the skill_usage_scope root (repo: the project root; user: $HOME). Leave unset to use .claude/observability. The data-dir scope ignores it. Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. |
| `skill_usage_git_exclude` | boolean | `true` | Adds the repo-scope store's directory to .git/info/exclude when it sits inside a git work tree, so git status stays clean. On by default; machine-local, and never touches .gitignore or tracked files. Set false if your team deliberately commits the telemetry. |
| `skill_usage_max_bytes` | number<br>*min 1* | `10485760` | Size at which a skill-usage producer rotates skill-usage.jsonl to skill-usage.jsonl.1, replacing any older .1, so the pair stays near twice this value. Default 10485760. |
| `api_error_audit_enabled` | boolean | `true` | Emits turn-failure telemetry on API errors. On by default. |
| `config_change_audit_enabled` | boolean | `true` | Emits telemetry on config-source mutations. On by default. |
| `instructions_loaded_audit_enabled` | boolean | `true` | Emits telemetry on rule and instruction file loads. On by default. |
| `instructions_loaded_audit_log_session_start` | boolean | `false` | Makes the instructions-loaded-audit hook log session_start instruction loads. Off by default, because those loads are deterministic and high-volume. |
| `permission_denied_audit_enabled` | boolean | `true` | Emits telemetry on permission denials. On by default. |
| `pre_compact_audit_enabled` | boolean | `true` | Emits telemetry on context-compaction events. On by default. |
| `tool_failure_audit_enabled` | boolean | `true` | Emits telemetry on Write, Edit, and Bash tool failures. On by default. |
| `session_event_log_enabled` | boolean | `false` | Appends one JSON line per hook event to <session_event_log_dir>/sessions/<session_id>.jsonl, on every event the generated registry marks observable. Runs in the hooks module, so it needs mods on. Off (the default), no event starts a process; on, each event in an enabled category starts one. It also gates SessionEnd retention. |
| `session_event_log_dir` | string | `".observability/claude"` | Project-relative directory holding the per-session hook event log (sessions/) and the telemetry sink's hook-events.jsonl. Default .observability/claude. Absolute, drive, UNC, traversal and escaping paths are invalid, and the project root itself is refused. |
| `session_event_log_categories` | string | *(none)* | Comma-separated event categories to record (session, prompt, tool, permission, agent, task, turn, config, worktree, compaction, model, mcp, display, other). Empty, the default, records every category the registry marks observable. An unlisted category starts no process, and SessionEnd retention runs whatever the list. |
| `session_event_log_content` | boolean | `false` | Also records each event's top-level content strings (prompt, last_assistant_message, message, task text, error and the like) in the session event log; content the 64 KB read cap cuts is marked truncated. Off by default; has no effect while session_event_log_enabled is off. |
| `session_log_keep_sessions` | number<br>*min 1* | `30` | At SessionEnd, keeps the newest N session files regardless of age; default 30. A file is kept when it is among the newest N OR younger than session_log_keep_days. |
| `session_log_keep_days` | number<br>*min 1* | `14` | At SessionEnd, keeps every session file younger than N days regardless of count; default 14. A file is kept when it is younger than N days OR among the newest session_log_keep_sessions. |
| `session_log_pre_prune_command` | string | *(none)* | Command run detached at SessionEnd with one argument: a directory holding the session files about to be pruned, deleted on the next retention run after 24 hours. Leave unset to delete directly. Runs through bash -c, so only your own user settings can supply it. |
| `hook_events_max_bytes` | number<br>*min 1* | `10485760` | Size at which the telemetry sink rotates the shared hook-events.jsonl to hook-events.jsonl.1, replacing any older .1, so the pair stays near twice this value. Default 10485760. Applies whether or not the per-session event log is on. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open. Default 2. |

### How to set these

Set the options above for `session-telemetry@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
