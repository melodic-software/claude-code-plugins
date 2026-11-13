# Hook Telemetry Convention

A versioned, marketplace-wide contract for plugin hooks to emit structured execution telemetry. A hook
(the **producer**) emits one JSON envelope per run to a **sink** the consuming repo sets via
`HOOK_TELEMETRY_SINK`. The signal it carries, **this hook's own `duration_ms`, outcome, and findings**,
is what Claude Code's native OTEL cannot provide: its hook event reports all matching hooks together
([monitoring § Hook execution complete event](https://code.claude.com/docs/en/monitoring-usage#hook-execution-complete-event)),
and its per-invocation plugin hook event excludes third-party plugin content, which covers this
marketplace's hooks
([§ Hook plugin metrics event](https://code.claude.com/docs/en/monitoring-usage#hook-plugin-metrics-event)).
As of 2026-10-11; recheck when the first event reports one hook's duration and outcome, or the
second opens to third-party marketplace plugins.

This directory is the source of truth: `envelope.schema.json` (common fields), `data/<hook>.schema.json`
(per-hook payload), `CHANGELOG.md` (version history), `examples/` (worked fixtures).

## Mediator boundary

The producer and sink are decoupled, and neither imports the other. The producer writes an envelope to stdin
of whatever `HOOK_TELEMETRY_SINK` names; the sink interprets it. This lets sinks be written independently
(medley maps the envelope into its own event store) and lets a plugin ship telemetry that simply no-ops
where no sink is configured.

- **`HOOK_TELEMETRY_SINK` unset is a no-op.** The hook behaves exactly as it did before telemetry: same stdout,
  same exit code. Telemetry is purely additive.
- **Fire-and-forget.** The producer dispatches the sink in the background and returns immediately; it never
  waits on, nor fails because of, the sink.
- **Best-effort / lossy.** A slow or down sink drops the event silently. This contract is for observability
  ("find the slow hook"), **not** for must-not-lose data. Do not build accounting, billing, or audit-of-record
  on it.

## Sink path resolution

`HOOK_TELEMETRY_SINK` is the reserved value `@harness-ops`, or a **single executable path**, absolute
or relative to the consuming repo root. The producer resolves it before dispatch:

- **`@harness-ops`**: the harness-ops reference sink, through the launcher harness-ops rewrites at each
  SessionStart in its plugin data directory, `<data root>/harness-ops-<marketplace>/hook-telemetry-sink.sh`.
  The producer searches the parent of its own `CLAUDE_PLUGIN_DATA` when it has one (a plugin hook;
  either path separator), then `${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/data`. Precedence: of every
  `harness-ops-*` launcher found, the one modified most recently wins, whatever its name and
  whichever producer asks. harness-ops touches its launcher at each SessionStart, so the install
  that last started a session wins, and every producer sends to the same root. None found: the
  event is skipped, fail-open. The launcher carries harness-ops'
  `session_event_log_dir` and `hook_events_max_bytes`, so every producer's rows land in harness-ops'
  root, and deletes itself when its install is gone.
- **Any other value starting with `@`**: reserved for later sinks; the producer skips the event.
- **Absolute** (POSIX `/…` or Windows `X:\` / `X:/`): used as-is.
- **Relative** (e.g. `.claude/hooks/hook-telemetry-sink.sh`): joined onto the consuming repo root the
  producer already resolves for `data.file` (falling back to `$CLAUDE_PROJECT_DIR`); skipped fail-open if
  neither anchor is available, since a drifted hook CWD would resolve it incorrectly.

`@harness-ops` and a relative path are the portable, team-shared wiring forms: commit either in
`settings.json`, so every clone and worktree wires the same sink with no per-machine absolute path.
`@harness-ops` also needs no copy of the sink in the repository. Settings `env` values reach the
environment as written, with no shell expansion, so `${CLAUDE_PLUGIN_ROOT}` cannot name the
installed sink there. To pass arguments, wrap the sink in a script: the producer runs the value as a
single command.

- **Pointer**: for where plugin data directories live and that they survive updates, fetch
  [plugins reference § Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
  and the `CLAUDE_CONFIG_DIR` row of [environment variables](https://code.claude.com/docs/en/env-vars) live.
- **As of**: 2026-11-08
- **Recheck trigger**: either page moves `${CLAUDE_PLUGIN_DATA}` out of `<config dir>/plugins/data`
  or changes how `<id>` is formed.

- **Pointer**: when checking where Claude Code expands `${VAR}` references in configuration, fetch
  [MCP § Environment variable expansion in `.mcp.json`](https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcp-json)
  live.

## The envelope (common fields)

Every event, from every hook, carries these seven fields. All are required and always present.

| Field | Type | Meaning |
|-------|------|---------|
| `schema_version` | string (SemVer) | Version of this envelope contract. |
| `timestamp` | string (RFC 3339, UTC) | Instant the hook finished. True UTC: the `Z` is not a local-time lie. |
| `hook` | string | Producer hook id, e.g. `desktop-notification`. **Not** CC's `hook_name` (event:matcher). Keys data-schema discovery. |
| `hook_event` | string | The triggering event: `PostToolUse`, `SessionStart`, `ConfigChange`, `WorktreeCreate`, …, or for a mod its event, such as `tool.call`. A **free string**, not an enum, because the event vocabulary grows and custom events exist. |
| `status` | string | Universal execution outcome (documented value set, not a closed enum). See below. |
| `duration_ms` | integer (≥ 0) | **This hook's** runtime in milliseconds. Not CC's aggregate `total_duration_ms`. |
| `data` | object | Per-hook payload; always present (at minimum `{}`). See "Per-hook data". |

### Correlation keys (optional, since 1.1)

Four optional spine fields, each copied verbatim from the hook payload by `hook::emit_telemetry` when
the payload carries the key with a plain id (`[A-Za-z0-9._-]+`), and omitted otherwise, never guessed.
A mod's emitter takes the same keys from the mod event and `$.session.id()` under the same plain-id
rule; a mod event carries no `prompt_id`, so its envelopes have none.
They sit between `duration_ms` and `data`. A hierarchy, coarsest first:

| Field | Source | Joins to |
|-------|--------|----------|
| `session_id` | payload `session_id` | The per-session event log and the per-session sink route. |
| `prompt_id` | payload `prompt_id` | The same turn's OpenTelemetry events: this contract's key for joining a local envelope to the OTel stream. |
| `tool_use_id` | payload `tool_use_id` on tool events | One tool call; finer than `prompt_id`. |
| `agent_id` | payload `agent_id` inside a subagent | The subagent that ran the hook. |

- **Pointer**: when joining `prompt_id` to OTel events, fetch
  [monitoring § Event correlation attributes](https://code.claude.com/docs/en/monitoring-usage#event-correlation-attributes)
  and [hooks § Common input fields](https://code.claude.com/docs/en/hooks#common-input-fields) live.

The library reads the payload the producer buffered: `HOOK_TELEMETRY_PAYLOAD` when set, else the
`INPUT` variable every fleet hook assigns from `hook::buffer_stdin`. A producer that buffers under
another name sets `HOOK_TELEMETRY_PAYLOAD` before it emits; a producer with no payload emits none of
the four. A sink on 1.0 sees four unknown keys and ignores them under the tolerate-unknown rule.

**Only the payload root is read.** A key of the same name nested inside `tool_input` or
`tool_response` is never taken, so a tool whose own parameter happens to be called `tool_use_id` or
`agent_id` cannot put a value on the spine. A consumer can therefore treat a present key as the
harness's own, not as tool-supplied input.

**A key may be absent on a large payload.** Selecting by depth costs more than the emitter can spend
on a payload carrying a whole file, so above 65536 bytes the library falls back to reading only the
region ahead of the first nested container. A key the payload carries after its first nested
container, such as one after `tool_input`, is omitted on a payload over that size. Absent still
means absent, never guessed, and never a value from somewhere else.
Tightening this without paying the cost is [#3784](https://github.com/melodic-software/claude-code-plugins/issues/3784).

- **Pointer**: when checking which fields a hook payload carries, fetch
  [hooks § Common input fields](https://code.claude.com/docs/en/hooks#common-input-fields) live.

Naming is snake_case throughout and aligns with Claude Code's own field names where the concept matches
(`hook_event`), and deliberately diverges where it does not (`hook` ≠ `hook_name`, `duration_ms` ≠
`total_duration_ms`) so a name never misleads.

### `status`: the universal outcome (documented value set)

`ok | error | skipped | blocked` is a **documented open string, not a closed JSON-Schema enum** (same encoding
as `hook_event`, and for the same reason: the set grows). A closed enum would *reject* a future value at
validation time, contradicting the tolerate-unknown rule below. These four express the outcome of *any* hook,
validated against the full medley hook set (formatters, guards, audit, action hooks):

| Value | Meaning |
|-------|---------|
| `ok` | The hook ran and did its job. |
| `error` | The hook ran but failed internally. |
| `skipped` | The hook did not apply (a no-op: wrong file type, disabled, nothing to do). |
| `blocked` | The hook intentionally blocked the operation (guard hooks: git-safety, branch-protection, secret-pattern-detection, …). Distinct from `error`. |

Domain detail, *what* a hook found rather than *whether* it ran, lives in `data`, never in `status`. Lint
findings are `data.findings`, because "found issues" is specific to formatters and not a universal outcome.
`cancelled` is intentionally excluded: a killed hook cannot self-report.

## Per-hook data

`data` carries everything not universal to all hooks. Its shape per producer is published at
`data/<hook>.schema.json`, **discovered by the envelope's `hook` value**. For `hook: "desktop-notification"`,
read `data/desktop-notification.schema.json` (`channels`, `notification_type`).

- **`data` is always present**, an object, possibly `{}`.
- **Generic sinks ignore `data`** and consume only the common envelope.
- **Unknown `hook`** (no matching data schema) → record the common fields, ignore `data`. Never hard-fail.

## Forward compatibility (don't break clients)

The whole point of a published contract is that independently-written sinks keep working as producers evolve.
Two rules make that hold:

1. **`data` evolves additive-only**: new keys may be added; existing keys are never silently removed,
   renamed, or type-changed (those require a deprecation cycle and a major bump).
2. **Consumers MUST ignore unknown keys AND MUST tolerate unknown enum values.** A sink reading an envelope
   from a newer producer must skip keys it does not recognize, and must treat an unrecognized `status` (or
   any future enum value) as a catch-all rather than crashing. Ignore-unknown-keys alone is not enough,
   because enum growth (e.g. a future `status`) needs the tolerate-unknown-enum rule too.

Both schema files set `additionalProperties: true`, which encodes only the **unknown-keys-tolerated** half of
these rules. The rest is **policy, enforced by review and the deprecation cycle below, not by the schema**:
`additionalProperties` says nothing about existing keys never being removed/renamed/type-changed, and a closed
`enum` would actively *reject* a new `status` value (which is why `status` is a documented open string, like
`hook_event`). Do not over-trust the schema as the enforcement boundary; it is the contract a reviewer reads.

## Deprecation policy

A field is marked **deprecated** in `CHANGELOG.md` for one minor cycle before it is removed. Removal, rename,
or type-change of any field is a major `schema_version` bump. This gives consumers a release window to adapt
before a breaking change lands.

## Versioning

`schema_version` (SemVer) versions the **envelope**. Per-hook `data` schemas churn independently under the
additive / ignore-unknown rules above and are **not** separately version-stamped (deferred as YAGNI). The
envelope version and a hook's `data` shape are decoupled on purpose.

A per-`data` version signal is **deferred, not designed out**: today a hook's `data` shape is discovered only
by the `hook` value, so a breaking `data` change would carry no version marker short of a whole-envelope major
bump. **Trigger**: when a producer first needs a *breaking* `data` change, add an optional per-payload schema
identifier (a `data_schema` URI, à la CloudEvents `dataschema`) rather than bumping the envelope. It is
additive (optional field), so it ships without breaking existing consumers.

## The envelope schema is executed by the test-side check

`envelope.schema.json` is the single source of the envelope field list. `check_envelope` in
[`lib/hook-test-sink.sh`](../../../lib/hook-test-sink.sh) reads its `required` keys, property types and
minimums with `jq` and validates each envelope a hook suite captures. No producer or sink validates at
runtime, and the check covers the common envelope only: the per-hook `data` schemas and the policy rules
above are held by review and the deprecation cycle. A suite carries no transcribed field list of its own.

## Adoption (adopt-by-copy)

The emit function is **co-located in each plugin's `hooks/hook-utils.sh`**, because plugins are runtime-isolated
under `${CLAUDE_PLUGIN_ROOT}`, so there is no shared library to import. Each copy is generated from the
canonical `lib/hook-utils.sh`, and `scripts/sync-shared-copies.sh --check` fails on drift. This mirrors the
standards-repo "adopt by copy" pattern.

A mod emits from its own hooks module instead, in TypeScript: context-usage's
`hooks/register.tsx` builds the same envelope, resolves `HOOK_TELEMETRY_SINK` by the rules above
(`@harness-ops` through `$.fs.list` and `$.fs.stat` modification times of the config dir's plugin
data root, since a mod has no
`CLAUDE_PLUGIN_DATA`; a relative path joins onto the session's project root, else
`CLAUDE_PROJECT_DIR`), and starts the
sink fire-and-forget through `$.process.run`. Its envelope is checked by the plugin's own
`claude plugin test` cases rather than by `check_envelope`.

## Consuming (sink side)

A repo **subscribes** by setting `HOOK_TELEMETRY_SINK` (committed in `settings.json`) to
`@harness-ops`, or to a relative path of an
executable that reads one envelope on stdin and maps the common fields into its own store. The
envelope arrives as one JSON document; since the shared library's 2026-09-02 builtin emitter it is a
single compact line (`jq -c` shape, no trailing CR), where earlier producers wrote jq's
pretty-printed form. A sink must parse the document as JSON, never by line or byte layout. The sink:

- consumes only the common envelope unless it specifically handles a given `hook`'s `data`;
- ignores unknown keys and treats an unrecognized `status` as a catch-all (see Forward compatibility);
- never crashes and never writes to stdout, since it runs fire-and-forget, exec'd as a single command per event.

That is the whole consumer contract. Any number of independently-written sinks can subscribe to the same
producers without coordinating with them or each other.

**Store anchoring.** A sink, or a producer that writes its own rows, whose store path is relative to
the project joins it onto the main checkout: the directory that holds the repository's common `.git`
directory, which `git rev-parse --git-common-dir` prints. The session's working tree is the wrong
anchor. In a linked worktree, `git rev-parse --show-toplevel` prints the worktree, so rows written
there are deleted when the worktree is removed, and a reader in the main checkout never sees them.
Without spawning git, follow the worktree's `.git` file (`gitdir: <path>`) to its `commondir` file;
a relative `commondir` path resolves against that gitdir. The anchor is the parent of the common
directory when that directory is named `.git`, so a bare repository cloned into `proj/.git` anchors
at `proj/`. A directory outside any git checkout keeps its own directory, and so does a submodule (its
gitdir has no `commondir`), a worktree of a bare repository whose directory has another name, such
as `proj.git`, and a `.git` file git did not register: the gitdir must be `<common>/worktrees/<name>`
and its `gitdir` file must name this tree, compared as physical paths. A reader resolves the same anchor, so one store serves every worktree of a
repository, and retention that counts sessions counts those of every worktree together. The containment checks a sink applies hold against the
anchor. The harness-ops reference sink, its retention hook and its reader share one resolver:
`slog_anchor_to` in `plugins/harness-ops/hooks/session-log-lib.sh`.

**Sink routing by session (reference sink, harness-ops 0.42.11).** Since contract 1.1 every producer
that emits through `hook::emit_telemetry` carries the payload's `session_id` on the envelope spine
(see "Correlation keys" above), so a sink needs nothing from the producer to file rows per session.
The harness-ops reference sink reads the spine key first and falls back to `data.session_id`, the
key the nine harness-ops audit hooks added under the additive rule before 1.1 and still send: an
envelope carrying a well-formed id is appended to `<root>/sessions/<session_id>.jsonl` beside the
per-session event log, and an envelope without one (a producer on 1.0, or a hook whose payload
carries no session) goes to the shared `<root>/hook-events.jsonl`. The per-session report therefore
covers every fleet producer from their 1.1 versions on (#3758, which finishes the thread #930
opened).

A sink's own store shape is the sink's business, not this contract's. A store a reader has to
reconcile per query is the sink's own defect. The harness-ops reference sink writes ONE record shape
on both routes, alongside the per-session event log's rows: the routes differ by destination and by
whether the record carries `session_id`, and `hook_event_name` names the event on every row, so no
reader normalizes an event key. The key set and the group each route contributes are stated once,
where the formatter every writer calls lives:
`plugins/harness-ops/hooks/session-log-lib.sh` (`slog_event_record_to`).

## Implementers

| Producer | `hook` value | Data schema |
|----------|--------------|-------------|
| `desktop-notification` plugin | `desktop-notification` | `data/desktop-notification.schema.json` |
| `guardrails` plugin | `secret-pattern-detection` | `data/secret-pattern-detection.schema.json` |
| `guardrails` plugin | `hardcoded-path-check` | `data/hardcoded-path-check.schema.json` |
| `guardrails` plugin | `cli-flag-verify` | `data/cli-flag-verify.schema.json` |
| `guardrails` plugin | `stale-path-verify` | `data/stale-path-verify.schema.json` |
| `guardrails` plugin | `block-no-verify` | `data/block-no-verify.schema.json` |
| `guardrails` plugin | `block-dangerous-git` | `data/block-dangerous-git.schema.json` |
| `guardrails` plugin | `block-noncanonical-commit` | `data/block-noncanonical-commit.schema.json` |
| `guardrails` plugin | `flag-commit-pr-skill-bypass` | `data/flag-commit-pr-skill-bypass.schema.json` |
| `guardrails` plugin | `workflow-resilience-check` | `data/workflow-resilience-check.schema.json` |
| `guardrails` plugin | `block-windows-drive-tmp` | `data/block-windows-drive-tmp.schema.json` |
| `guardrails` plugin | `block-exported-msys-pathconv` | `data/block-exported-msys-pathconv.schema.json` |
| `guardrails` plugin | `block-root-delete-target` | `data/block-root-delete-target.schema.json` |
| `harness-ops` plugin | `api-error-audit` | `data/api-error-audit.schema.json` |
| `harness-ops` plugin | `config-change-audit` | `data/config-change-audit.schema.json` |
| `harness-ops` plugin | `instructions-loaded-audit` | `data/instructions-loaded-audit.schema.json` |
| `harness-ops` plugin | `permission-denied-audit` | `data/permission-denied-audit.schema.json` |
| `harness-ops` plugin | `pre-compact-audit` | `data/pre-compact-audit.schema.json` |
| `harness-ops` plugin | `skill-usage-audit` (two producers: PostToolUse/Skill and UserPromptExpansion, per the schema) | `data/skill-usage-audit.schema.json` |
| `harness-ops` plugin | `tool-failure-audit` | `data/tool-failure-audit.schema.json` |
| `autonomy` plugin | `lane-stop-gate` | `data/lane-stop-gate.schema.json` |
| `disk-hygiene` plugin | `destructive-guard` | `data/destructive-guard.schema.json` |
| `disk-hygiene` plugin | `guard-launch-monitor` | `data/guard-launch-monitor.schema.json` |
| `context-usage` plugin (mod) | `zone-crossing-inject` (events `tool.call`, `prompt.submit` and `turn.complete`, per the schema) | `data/zone-crossing-inject.schema.json` |
| `context-usage` plugin | `post-compact-mark` | `data/post-compact-mark.schema.json` |
