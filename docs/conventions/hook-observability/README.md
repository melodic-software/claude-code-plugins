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
there is no runtime JSON output field by this name.** **Rollout status: near-complete.** As of
2026-07-23, 30 of the 31 wired `type: "command"` handlers across the fleet's 15 hook-bearing
plugins declare `statusMessage`; the sole remaining holdout is
`plugins/disk-hygiene/hooks/hooks.json`. Tracked against
melodic-software/claude-code-plugins#836 (this doc landed first per the convention-registry rule;
adoption was the follow-up wave, now all but one site complete — close #836 once `disk-hygiene`
declares it or is recorded as a deliberate exception). Wording convention: a present-tense gerund
phrase naming what the hook is doing, specific to the tool or check
(`"Formatting Go imports..."`, `"Checking for secrets..."`, `"Recording tool-failure
telemetry..."`) — not a generic `"Running hook..."`.

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

This is the doctrine that fleet hook scripts cite in comments as the **"dim-9 doctrine"** — the
label names *this* visible-skip rule and nothing more, and this section is its authoritative
definition. (The `dim-N` numbers are an informal fleet-conformance shorthand — e.g. dim-8 = the
uniform setup-skill wave, dim-11 = seam phrasing — with no central registry defining the numbering;
giving the whole scheme a documented home is a separate follow-up, tracked outside this doc.)

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
**not visible**, regardless of intent. `scripts/check-silent-skips.sh` **still treats a bare
stderr write as a sanctioned visibility signal as of this doc's introduction** — that is incorrect
for the exit-0 skip shapes the gate inspects, and the gate does not yet enforce the rule this doc
states. **Gate correction is pending**, scoped into the same fleet-adoption follow-up PR (against
issue #836) that converts the 9 fleet sites currently relying on that leniency
(`plugins/guardrails/hooks/*.sh`) — the gate and its dependent sites land together so CI never
regresses between them. Once corrected, a quiet skip must use one of the sanctioned helper calls
or an explicit `# silent-skip-ok: <reason>` annotation.

### 3. OTel-style telemetry envelope

Every wired producer hook emits one envelope per meaningful-outcome run via `hook::emit_telemetry`
(`lib/hook-utils.sh`) to the consumer-opted-in `HOOK_TELEMETRY_SINK`. Full schema and adoption
list: [`docs/conventions/hook-telemetry/`](../hook-telemetry/README.md) — this doc does not
restate that shape, only the adoption requirement: **every hook wired in a plugin's `hooks.json`
emits it for each meaningful outcome it produces** (a check that ran and returned ok / blocked /
skipped-for-cause) — a pure inapplicability short-circuit before any check logic runs (wrong tool
type, excluded path, missing prerequisite) does not need one; see the Conformance section below
for the precise rule and why.

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
- The hook emits the telemetry envelope for every **meaningful outcome** — a check that ran and
  produced a result (ok / blocked / skipped-for-cause). A pure inapplicability short-circuit
  (wrong tool type, excluded path, empty content, outside the project) that fires before any
  check logic runs carries no diagnostic information and does not need one — this matches how
  every current telemetry-emitting hook in the fleet is already shaped.

`scripts/check-silent-skips.sh` mechanically enforces the second point for the `command -v`-gated
shapes it recognizes, **once its pending gate correction lands** (see the systemMessage section
above) — a bare stderr write does not actually satisfy the doctrine (exit-0 stderr is invisible
per the fresh fetch above), even though the gate does not yet reject it. After that correction, a
quiet skip needs a sanctioned helper call or an explicit `# silent-skip-ok:` annotation.
