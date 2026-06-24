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

## The envelope (common fields)

Every event, from every hook, carries these seven fields. All are required and always present.

| Field | Type | Meaning |
|-------|------|---------|
| `schema_version` | string (SemVer) | Version of this envelope contract. |
| `timestamp` | string (RFC 3339, UTC) | Instant the hook finished. True UTC — the `Z` is not a local-time lie. |
| `hook` | string | Producer hook id, e.g. `markdown-format`. **Not** CC's `hook_name` (event:matcher). Keys data-schema discovery. |
| `hook_event` | string | The triggering event: `PostToolUse`, `SessionStart`, `ConfigChange`, `WorktreeCreate`, … A **free string**, not an enum — the event vocabulary grows, and custom events exist. |
| `status` | string (enum) | Universal execution outcome. See below. |
| `duration_ms` | integer (≥ 0) | **This hook's** runtime in milliseconds. Not CC's aggregate `total_duration_ms`. |
| `data` | object | Per-hook payload; always present (at minimum `{}`). See "Per-hook data". |

Naming is snake_case throughout and aligns with Claude Code's own field names where the concept matches
(`hook_event`), and deliberately diverges where it does not (`hook` ≠ `hook_name`, `duration_ms` ≠
`total_duration_ms`) so a name never misleads.

### `status` — the universal outcome enum

`ok | error | skipped | blocked`. These express the outcome of *any* hook, validated against the full medley
hook set (formatters, guards, audit, action hooks):

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

Both schema files set `additionalProperties: true` to encode rule 1 at the schema level.

## Deprecation policy

A field is marked **deprecated** in `CHANGELOG.md` for one minor cycle before it is removed. Removal, rename,
or type-change of any field is a major `schema_version` bump. This gives consumers a release window to adapt
before a breaking change lands.

## Versioning

`schema_version` (SemVer) versions the **envelope**. Per-hook `data` schemas churn independently under the
additive / ignore-unknown rules above and are **not** separately version-stamped (deferred as YAGNI). The
envelope version and a hook's `data` shape are decoupled on purpose.

## Schemas are contract-docs, not machine-enforced

The JSON schemas here are **not machine-enforced** — no validator is wired into producer or sink. They are
the human-readable, reviewable contract; conformance is checked by hand and by `jq` required-key assertions
(producers and sinks each carry their own). Treat the schemas as the authority a reviewer reads, not a
runtime gate.

## Adoption (adopt-by-copy)

The emit function is **co-located in each plugin's `hooks/hook-utils.sh`** — plugins are runtime-isolated
under `${CLAUDE_PLUGIN_ROOT}`, so there is no shared library to import. The first implementer
(`markdown-formatter`) carries its own copy. **The moment a second hook needs to emit, extract a canonical
copy and add a drift-check in the same change** — copy once, then consolidate, so the two copies never drift
unwatched. This mirrors the standards-repo "adopt by copy" seam.

## Implementers

| Producer | `hook` value | Data schema |
|----------|--------------|-------------|
| `markdown-formatter` plugin | `markdown-format` | `data/markdown-format.schema.json` |
