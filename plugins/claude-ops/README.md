# claude-ops

A Claude Code plugin for running Claude Code well over time — one cohesive
capability across five skills and a family of telemetry-emitter hooks.
Observability reads what your sessions actually did, known-issues tracks what
upstream has broken, changelog integration keeps your repo current with what
upstream has shipped, the plugins skill keeps your own plugin fleet current, a
re-runnable `setup` action settles where the known-issues registry lives,
and the `*-audit` hooks feed observability with per-hook execution telemetry
Claude Code's native OTEL cannot see.

## Skills

| Skill | What it does |
|---|---|
| `/claude-ops:observability` | Reads locally captured Claude Code telemetry — OTEL DuckDB store, machine-owned collector, optional Aspire dashboard, hook-event JSONL, ccusage — and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/claude-ops:known-issues` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/claude-ops:changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (impact triage, no edits), `status` (applied versions from git history), and `apply` (full explore → research → interview → implement pipeline, explicit user intent only). |
| `/claude-ops:plugins` | Brings a machine's plugin fleet current on demand: marketplace refresh, updates for the plugins that actually load (including in-repo project/local-scope installs), new-catalog-plugin install per policy, and scope-divergence detection. Actions: `sync` (default, CLI-mediated mutations only), `audit` (read-only dry run), `converge` (the one action that can touch a committed `.claude/settings.json` — previews and confirms per plugin first). |
| `/claude-ops:setup` | `check` (default) reports the effective known-issues-registry and skill-usage-log destinations, their defaults, and path containment; `apply` routes personal option changes through Claude Code's plugin configuration prompt. |

## The audit hooks

Seven advisory `*-audit` telemetry emitters (across eight hook scripts —
`skill-usage-audit` has two producers, see below) emit the marketplace
[hook-telemetry envelope](../../docs/conventions/hook-telemetry/README.md) — one
JSON event per run carrying that hook's own `duration_ms`, outcome, and a
privacy-safe subject. Each is independently toggleable via its own `userConfig`
boolean (default **on**; see [Per-hook kill switches](#per-hook-kill-switches)).
The six pure emitters are a no-op until a consumer wires a sink (below);
`skill-usage-audit` is the exception — both its producers also write the shared
`skill-usage.jsonl` second store unconditionally (disable the whole feature with
`skill_usage_audit_enabled=false`, or relocate the store with the
`skill_usage_dir` option).

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

`instructions-loaded-audit` drops deterministic, high-volume `session_start`
loads by default; set `instructions_loaded_audit_log_session_start=true` to opt
back into logging them. A `stdin_read_timeout` option (seconds, default `2`)
bounds how long each hook waits for its payload before failing open.

Set them interactively with `/plugin configure claude-ops`, or headless on the
install command:

```shell
claude plugin install claude-ops@melodic-software --config skill_usage_audit_enabled=false
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
/plugin install claude-ops@melodic-software
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
  (`registry.json`), `check-all` output, and `--write` observability reports.
  By default nothing is written into your repository. Opt in for the registry
  via the `registry_dir` option (see Configuration) to keep it git-tracked and
  team-shared inside your repo instead.
- **Work-item and docs integration.** Where the skills propose follow-up work
  items or cross-reference quirks/workaround docs, they use whatever tracker
  and docs your project has (e.g. `gh issue create`, your `CLAUDE.md` /
  `.claude/rules`) and skip silently when there is none.

## Requirements

The audit hooks are Bash scripts (Git Bash on native Windows — install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)) and
use `jq`; without jq they fail open (no audit line is written).

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
- **`skill_usage_dir`** (string, optional) — project-relative directory where
  `skill-usage-audit` writes its `skill-usage.jsonl` second store (the
  "measuring skills" record, separate from the telemetry envelope); leave unset
  to use `.claude/observability`. The same containment rules apply. An invalid
  value produces a visible advisory and skips the second-store write; telemetry
  through an independently configured sink can still proceed.

Run `/claude-ops:setup` to validate this choice. Claude Code owns persistence through its plugin
configuration prompt; rerun setup afterward to verify the rendered value.

Remaining variability is covered by the env vars above and conventional
project-relative defaults; the bundled scripts make no outbound network calls
except `gh`/`curl` reads of GitHub and Claude status pages in the
known-issues skill.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
