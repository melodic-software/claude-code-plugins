# Hook Telemetry Convention

A versioned, marketplace-wide contract for plugin hooks to emit structured execution telemetry. A hook
(the **producer**) emits one JSON envelope per run to a **sink** the consuming repo sets via
`HOOK_TELEMETRY_SINK`. The signal it carries — **this hook's own `duration_ms`, outcome, and findings** —
is what Claude Code's native OTEL cannot provide (CC reports an aggregate `total_duration_ms` across all
hooks and excludes third-party plugin content).

This directory is the source of truth: `envelope.schema.json` (common fields), `data/<hook>.schema.json`
(per-hook payload), `CHANGELOG.md` (version history), `examples/` (worked fixtures).

## Mediator boundary

The producer and sink are decoupled — neither imports the other. The producer writes an envelope to stdin
of whatever `HOOK_TELEMETRY_SINK` names; the sink interprets it. This lets sinks be written independently
(medley maps the envelope into its own event store) and lets a plugin ship telemetry that simply no-ops
where no sink is configured.

- **`HOOK_TELEMETRY_SINK` unset → no-op.** The hook behaves exactly as it did before telemetry: same stdout,
  same exit code. Telemetry is purely additive.
- **Fire-and-forget.** The producer dispatches the sink in the background and returns immediately; it never
  waits on, nor fails because of, the sink.
- **Best-effort / lossy.** A slow or down sink drops the event silently. This contract is for observability
  ("find the slow hook"), **not** for must-not-lose data. Do not build accounting, billing, or audit-of-record
  on it.

## Sink path resolution

`HOOK_TELEMETRY_SINK` is a **single executable path** — absolute, or relative to the consuming repo root.
The producer resolves it before dispatch:

- **Absolute** (POSIX `/…` or Windows `X:\` / `X:/`) — used as-is.
- **Relative** (e.g. `.claude/hooks/hook-telemetry-sink.sh`) — joined onto the consuming repo root the
  producer already resolves for `data.file` (falling back to `$CLAUDE_PROJECT_DIR`); skipped fail-open if
  neither anchor is available, since a drifted hook CWD would resolve it incorrectly.

Relative is the portable, team-shared wiring form. Claude Code injects `settings.json` `env` values
**literally** — no `${VAR}` expansion (that is a `.mcp.json`-only feature) — so a relative path committed in
`settings.json` is the only clone-portable, worktree-safe way to wire a sink without a per-machine absolute
path. To pass arguments, wrap the sink in a script: the value is exec'd as a single command.

## The envelope (common fields)

Every event, from every hook, carries these seven fields. All are required and always present.

| Field | Type | Meaning |
|-------|------|---------|
| `schema_version` | string (SemVer) | Version of this envelope contract. |
| `timestamp` | string (RFC 3339, UTC) | Instant the hook finished. True UTC — the `Z` is not a local-time lie. |
| `hook` | string | Producer hook id, e.g. `markdown-format`. **Not** CC's `hook_name` (event:matcher). Keys data-schema discovery. |
| `hook_event` | string | The triggering event: `PostToolUse`, `SessionStart`, `ConfigChange`, `WorktreeCreate`, … A **free string**, not an enum — the event vocabulary grows, and custom events exist. |
| `status` | string | Universal execution outcome (documented value set, not a closed enum). See below. |
| `duration_ms` | integer (≥ 0) | **This hook's** runtime in milliseconds. Not CC's aggregate `total_duration_ms`. |
| `data` | object | Per-hook payload; always present (at minimum `{}`). See "Per-hook data". |

Naming is snake_case throughout and aligns with Claude Code's own field names where the concept matches
(`hook_event`), and deliberately diverges where it does not (`hook` ≠ `hook_name`, `duration_ms` ≠
`total_duration_ms`) so a name never misleads.

### `status` — the universal outcome (documented value set)

`ok | error | skipped | blocked` — a **documented open string, not a closed JSON-Schema enum** (same encoding
as `hook_event`, and for the same reason: the set grows). A closed enum would *reject* a future value at
validation time, contradicting the tolerate-unknown rule below. These four express the outcome of *any* hook,
validated against the full medley hook set (formatters, guards, audit, action hooks):

| Value | Meaning |
|-------|---------|
| `ok` | The hook ran and did its job. |
| `error` | The hook ran but failed internally. |
| `skipped` | The hook did not apply (no-op — wrong file type, disabled, nothing to do). |
| `blocked` | The hook intentionally blocked the operation (guard hooks: git-safety, branch-protection, secret-pattern-detection, …). Distinct from `error`. |

Domain detail — *what* a hook found, not *whether* it ran — lives in `data`, never in `status`. Lint
findings are `data.findings`, because "found issues" is specific to formatters and not a universal outcome.
`cancelled` is intentionally excluded: a killed hook cannot self-report.

## Per-hook data

`data` carries everything not universal to all hooks. Its shape per producer is published at
`data/<hook>.schema.json`, **discovered by the envelope's `hook` value**. For `hook: "markdown-format"`,
read `data/markdown-format.schema.json` (`tool`, `file`, `findings`).

- **`data` is always present** — an object, possibly `{}`.
- **Generic sinks ignore `data`** and consume only the common envelope.
- **Unknown `hook`** (no matching data schema) → record the common fields, ignore `data`. Never hard-fail.

## Forward compatibility (don't break clients)

The whole point of a published contract is that independently-written sinks keep working as producers evolve.
Two rules make that hold:

1. **`data` evolves additive-only** — new keys may be added; existing keys are never silently removed,
   renamed, or type-changed (those require a deprecation cycle and a major bump).
2. **Consumers MUST ignore unknown keys AND MUST tolerate unknown enum values.** A sink reading an envelope
   from a newer producer must skip keys it does not recognize, and must treat an unrecognized `status` (or
   any future enum value) as a catch-all rather than crashing. Ignore-unknown-keys alone is not enough —
   enum growth (e.g. a future `status`) needs the tolerate-unknown-enum rule too.

Both schema files set `additionalProperties: true`, which encodes only the **unknown-keys-tolerated** half of
these rules. The rest is **policy, enforced by review and the deprecation cycle below — not by the schema**:
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
bump. **Trigger** — when a producer first needs a *breaking* `data` change, add an optional per-payload schema
identifier (a `data_schema` URI, à la CloudEvents `dataschema`) rather than bumping the envelope. It is
additive (optional field), so it ships without breaking existing consumers.

## Schemas are contract-docs, not machine-enforced

The JSON schemas here are **not machine-enforced** — no validator is wired into producer or sink. They are
the human-readable, reviewable contract; conformance is checked by hand and by `jq` required-key assertions
(producers and sinks each carry their own). Treat the schemas as the authority a reviewer reads, not a
runtime gate.

## Adoption (adopt-by-copy)

The emit function is **co-located in each plugin's `hooks/hook-utils.sh`** — plugins are runtime-isolated
under `${CLAUDE_PLUGIN_ROOT}`, so there is no shared library to import. The first implementer
(`markdown-format`) carries its own copy. **The moment a second hook needs to emit, extract a canonical
copy and add a drift-check in the same change** — copy once, then consolidate, so the two copies never drift
unwatched. This mirrors the standards-repo "adopt by copy" seam.

## Consuming (sink side)

A repo **subscribes** by setting `HOOK_TELEMETRY_SINK` (relative, committed in `settings.json`) to an
executable that reads one envelope on stdin and maps the common fields into its own store. The sink:

- consumes only the common envelope unless it specifically handles a given `hook`'s `data`;
- ignores unknown keys and treats an unrecognized `status` as a catch-all (see Forward compatibility);
- never crashes and never writes to stdout — it runs fire-and-forget, exec'd as a single command per event.

That is the whole consumer contract: any number of independently-written sinks can subscribe to the same
producers without coordinating with them or each other.

## Implementers

| Producer | `hook` value | Data schema |
|----------|--------------|-------------|
| `markdown-format` plugin | `markdown-format` | `data/markdown-format.schema.json` |
| `typos-format` plugin | `typos-format` | `data/typos-format.schema.json` |
| `ruff-format` plugin | `ruff-format` | `data/ruff-format.schema.json` |
| `go-format` plugin | `go-format` | `data/go-format.schema.json` |
| `bash-format` plugin | `bash-format` | `data/bash-format.schema.json` |
| `biome-format` plugin | `biome-format` | `data/biome-format.schema.json` |
| `powershell-format` plugin | `powershell-format` | `data/powershell-format.schema.json` |
| `eol-normalizer` plugin | `eol-normalizer` | `data/eol-normalizer.schema.json` |
| `actionlint` plugin | `actionlint-check` | `data/actionlint-check.schema.json` |
| `desktop-notification` plugin | `desktop-notification` | `data/desktop-notification.schema.json` |
| `guardrails` plugin | `secret-pattern-detection` | `data/secret-pattern-detection.schema.json` |
| `guardrails` plugin | `hardcoded-path-check` | `data/hardcoded-path-check.schema.json` |
| `guardrails` plugin | `cli-flag-verify` | `data/cli-flag-verify.schema.json` |
| `guardrails` plugin | `stale-path-verify` | `data/stale-path-verify.schema.json` |
| `guardrails` plugin | `block-no-verify` | `data/block-no-verify.schema.json` |
| `guardrails` plugin | `block-hook-bypass` | `data/block-hook-bypass.schema.json` |
| `guardrails` plugin | `block-dangerous-git` | `data/block-dangerous-git.schema.json` |
| `guardrails` plugin | `block-noncanonical-commit` | `data/block-noncanonical-commit.schema.json` |
| `guardrails` plugin | `flag-commit-pr-skill-bypass` | `data/flag-commit-pr-skill-bypass.schema.json` |
| `guardrails` plugin | `workflow-resilience-check` | `data/workflow-resilience-check.schema.json` |
| `claude-ops` plugin | `api-error-audit` | `data/api-error-audit.schema.json` |
| `claude-ops` plugin | `config-change-audit` | `data/config-change-audit.schema.json` |
| `claude-ops` plugin | `instructions-loaded-audit` | `data/instructions-loaded-audit.schema.json` |
| `claude-ops` plugin | `permission-denied-audit` | `data/permission-denied-audit.schema.json` |
| `claude-ops` plugin | `pre-compact-audit` | `data/pre-compact-audit.schema.json` |
| `claude-ops` plugin | `skill-usage-audit` (two producers: PostToolUse/Skill and UserPromptExpansion — see schema) | `data/skill-usage-audit.schema.json` |
| `claude-ops` plugin | `tool-failure-audit` | `data/tool-failure-audit.schema.json` |
| `autonomy` plugin | `lane-stop-gate` | `data/lane-stop-gate.schema.json` |
| `context-guard` plugin | `zone-crossing-inject` (two producers: PostToolBatch and UserPromptSubmit — see schema) | `data/zone-crossing-inject.schema.json` |
| `context-guard` plugin | `zone-gate` | `data/zone-gate.schema.json` |
| `context-guard` plugin | `post-compact-mark` | `data/post-compact-mark.schema.json` |
