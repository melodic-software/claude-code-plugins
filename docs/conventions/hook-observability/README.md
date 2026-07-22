# Hook observability — status, failure, and telemetry surfaces for fleet hooks

Owner doc for the three observability surfaces every fleet hook declares or emits: a during-run
status label, a user-visible notice when a runtime prerequisite is missing, and the fleet's
telemetry envelope. The [plugin philosophy](../../PLUGIN-PHILOSOPHY.md) owns the posture rule —
advisory-versus-blocking, fail-open-versus-closed; this doc owns which of the three surfaces a
given situation uses and how each is shaped.

Grounded against the official Claude Code hooks reference
(<https://code.claude.com/docs/en/hooks>, fetched 2026-07-22) — every field name, cap, and timing
claim below is sourced from that fetch, not from training-data recall, per this repo's own
research-verification discipline.

## The three surfaces

### 1. `statusMessage` — config, not runtime output

A static field on a `hooks.json` **handler object**, sibling of `type`/`command`/`timeout`/`if`:

```json
{
  "type": "command",
  "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/go-format.sh",
  "timeout": 15,
  "statusMessage": "Formatting Go imports..."
}
```

Displayed as the UI spinner label while the hook process runs. **A hook script never emits this —
there is no runtime JSON output field by this name.** Every command-hook handler in the fleet
declares one. Wording convention: a present-tense gerund phrase naming what the hook is doing,
specific to the tool or check (`"Formatting Go imports..."`, `"Checking for secrets..."`,
`"Recording tool-failure telemetry..."`) — not a generic `"Running hook..."`.

### 2. `systemMessage` — user-visible, scoped to silently-skipped features

An exit-0 JSON output field (`hookSpecificOutput` sibling), 10,000-character cap, shown to the
user immediately. Composed via `hook::emit_channels` / `hook::emit_skip_notice`
(`lib/hook-utils.sh`) alongside `additionalContext` in one JSON document — Claude Code parses a
hook's entire stdout as a single document, so a hook with both agent-channel content and a
pending notice must compose them there, never `printf` twice.

**Scope — required for exactly one situation:** a missing runtime prerequisite (binary, config
file, `jq`) causes the hook to silently no-op instead of performing its check. Doctrine
(`lib/hook-utils.sh:26-30`): *"a missing runtime prerequisite must surface to BOTH the agent
(additionalContext) and the user (systemMessage) — a silently skipped feature is a defect."*

**Not required** for two situations that are already visible or already correctly agent-scoped:

- **Exit-2 blocking paths.** A `PreToolUse` hook that blocks a tool call via exit code 2 is
  already user-visible through Claude Code's own permission-denial UI. An additional
  `systemMessage` on top of a block would be redundant, not more observable.
- **Legitimate advisory findings.** A hook that surfaces a finding to Claude for it to act on
  (e.g. a lint result, a suggested fix) belongs on `additionalContext` only — that is the correct
  channel for agent-actionable content, not a gap.

**Repeat-notice discipline.** A missing-prerequisite notice behind a broad matcher (every
`Write|Edit`, every `Bash` call) must not repeat on every invocation. Use `hook::require_jq`
(wraps `hook::notice_once` + `hook::emit_skip_notice`) for a missing-`jq` gate, or pair
`hook::notice_once` with `hook::emit_skip_notice` directly for a non-`jq` prerequisite. A raw,
unguarded `hook::emit_skip_notice` call on a broad-matcher hook is a conformance defect.

**Important exit-code caveat, grounded in the fresh fetch:** on exit 0, **stderr is never shown to
the user or the agent** — only stdout JSON is parsed. A bare `echo "..." >&2; exit 0` skip is
**not visible**, regardless of intent. `scripts/check-silent-skips.sh` previously treated a bare
stderr write as a sanctioned visibility signal; that was incorrect for the exit-0 skip shapes the
gate inspects and has been corrected (see Conformance below) — a quiet skip must use one of the
sanctioned helper calls or an explicit `# silent-skip-ok: <reason>` annotation.

### 3. OTel-style telemetry envelope

Every wired producer hook emits one envelope per run via `hook::emit_telemetry`
(`lib/hook-utils.sh`) to the consumer-opted-in `HOOK_TELEMETRY_SINK`. Full schema and adoption
list: [`docs/conventions/hook-telemetry/`](../hook-telemetry/README.md) — this doc does not
restate that shape, only the adoption requirement: **every hook wired in a plugin's `hooks.json`
emits it**, no exceptions for hooks with multiple exit paths (each path emits its own envelope
with the status that fits it).

**Why a local file sink, not a real OTel exporter.** Claude Code strips every `OTEL_*` exporter
environment variable from hook subprocesses it spawns
(<https://code.claude.com/docs/en/monitoring-usage#administrator-configuration>) — a hook process
cannot emit real OpenTelemetry even if it tried. The file-sink envelope is the only telemetry
surface available to a hook; this is a grounded constraint, not an oversight.

**Deferred: `prompt_id` correlation.** Hook input JSON carries a `prompt_id` field (Claude Code
v2.1.196+) that matches the `prompt.id` attribute on real OpenTelemetry events, which would let
external tooling correlate a hook's local envelope with the same turn's real OTel stream. Adding
it is a `hook-telemetry` schema change (`schema_version` 1.0 → 1.1) touching every producer's
`data_json` construction — out of scope for this doc's three-surface convention. Tracked at
melodic-software/claude-code-plugins#930.

## What this convention is not

- **Not a new telemetry schema.** The envelope shape is `hook-telemetry`'s concern; this doc only
  states the adoption requirement.
- **Not a blanket "add systemMessage everywhere" rule.** Scoped narrowly to the
  missing-prerequisite-skip case; over-applying it to blocking paths or advisory findings is
  itself a conformance defect (redundant user noise, or misrouting agent-actionable content to
  the user channel).
- **Not a UI feature.** No native "verbose hooks" toggle exists in Claude Code as of 2026-07-22
  (confirmed against the same fresh fetch this doc cites) — `statusMessage` and `systemMessage`
  are the sanctioned surfaces available today. An upstream feature request for a native
  verbose-hooks UI toggle is tracked separately, outside this repo.

## Conformance

Fleet audits check, per wired producer hook:

- Every `command`-type handler in its `hooks.json` declares a `statusMessage`.
- Every missing-prerequisite skip path emits a `systemMessage` (via `hook::require_jq` or
  `hook::notice_once` + `hook::emit_skip_notice`), gated so it fires once per session on a broad
  matcher.
- The hook emits the telemetry envelope on every exit path.

`scripts/check-silent-skips.sh` enforces the second point mechanically for the `command -v`-gated
shapes it recognizes — a bare stderr write no longer satisfies it (exit-0 stderr is invisible per
the fresh fetch above); a quiet skip needs a sanctioned helper call or an explicit
`# silent-skip-ok:` annotation.
