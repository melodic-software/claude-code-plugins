---
outcome: brief-locked
tier: A
date: 2026-08-17
---

# context-budget — plan

## Brief

### Goal

Ship a `context-budget` plugin whose single skill, `/context-budget:audit`, makes a session's fixed
startup payload **measurable per item**, explains each contributor in operator terms, and — behind an
explicit override — applies the trims the operator approves.

The novel capability is **per-tool attribution**. `/context` already itemises skills, agents and MCP
tools; it does not and structurally cannot itemise built-in tool schemas, which are the largest
single contributor (35.9k of a 35.3k-headline session here, across two lump-sum rows). A/B
differencing against a fixed baseline is the only route to that number, and it is compositional.

### Why this is not covered by what exists

| Incumbent | Owns | Does not own |
|---|---|---|
| `/context` | per-skill, per-agent, per-MCP-tool attribution | per-tool for built-ins (`systemToolDetails` is never populated; its emission site is dead) |
| `/doctor` | unused-skill/MCP/plugin detection (Check 1), always-resident summary (Check 6) | live measurement — it self-describes its figures as "disk-based estimates"; it is `disableModelInvocation: true` so **we cannot invoke it**, only route to it; it does not run headlessly |
| `claude-config:unhobble` | behavioural ablation of *project instruction surfaces* | token accounting; user-global scope; tool schemas |
| `claude-config:audit-instructions` | instruction text vs doctrine | anything measured |
| `context-guard` | live occupancy over time (zones) | baseline composition |
| `mcp-tools:audit` | author-side MCP tool-definition quality | consumer-side cost |

Uncontested territory: **measurement, baselining, per-item attribution, and the ablation ledger.**

### Constraints

1. **Cite, never transcribe.** No token figure, key list, bundled-skill inventory or threshold ships
   as skill content. The skill measures the consumer's machine and cites the mechanism. Method is
   durable; values are not. Governed by the marketplace's upstream-drift stamp discipline.
2. **Every lever carries an honesty category**, and a lever whose category cannot be determined is
   not offered: *removes weight* · *works but saves nothing here* · *blocks without saving* ·
   *vendor weight* · *unverified/undocumented (reported, never recommended)*.
3. **Writes are gated by a `PreToolUse` hook returning `permissionDecision: "ask"`** — the one
   mechanism that forces a prompt in auto mode (the classifier may still deny, but cannot silently
   approve). Documented as a **checkpoint, not a guarantee**: a `PermissionRequest` hook can allow it
   and `disableAllHooks` removes non-managed hooks.
4. **`~/.claude/settings.json` is never written — printed only.** Protected-path status does *not*
   produce a human confirmation; in auto mode the write routes to the classifier, which may approve
   with no human involved. "Never auto-approved" is a term of art meaning "not approved by a settings
   rule".
5. **Persistent config uses `permissions.deny`.** There is no `disallowedTools` key in settings.json.
6. **Pin and report the measured binary.** Multiple CLI installs with divergent category lists exist
   on real machines.
7. Report leads with **reclaimed reasoning space**, not cost. Smart zone, not dollars.

### Acceptance criteria

- Ranked per-item attribution for the built-in tool pool, derived by measurement, with the measured
  CLI version stamped on the report.
- Every lever presented with its honesty category and its official citation.
- A baseline/compare ledger in `${CLAUDE_PLUGIN_DATA}` recording before/after with the delta measured,
  not asserted.
- No skill content contains a transcribed token value, key inventory, or threshold.
- Degrades with a clear message — never a wrong number — when headless `/context` is unavailable.
- `/doctor`'s territory is routed to, never reimplemented.

### Named assumptions

- Headless `/context` keeps working. It is undocumented as `-p`-capable; treated as load-bearing but
  unsanctioned, with graceful degradation.
- The output format keeps changing. Parser is version-aware and fails loudly rather than parsing
  incorrectly.
- Deferral status is **measured per session**, not trusted from documentation
  (`anthropics/claude-code#40314` is unresolved).

### Deferred questions — USER-RESERVED

1. **Cloud/web surface scope.** `disableClaudeAiConnectors` is inert there and `deniedMcpServers` URL
   patterns do not match. Does the skill promise correctness there, or declare a narrower scope?
2. **Model-branched advice.** `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` is a large win on some models and a
   measured no-op on claude-opus-5. Branch, or measure-and-report only?
3. **The net-negative output-style lever** (~1k bought by discarding built-in engineering
   instructions): recommend, disclose-only, or omit?
4. Guided-wizard UX detail — ordering, grouping, explanation depth (Q15).

## Plan

### Phase 0 — resolve two blockers before building

- **Does the Agent SDK expose `get_context_usage`?** A structured object with exact integers and a
  `free|buffer|deferred|used` enum exists in the binary behind the control protocol. If reachable it
  removes markdown parsing entirely. **This decides the measurement engine's shape — resolve first.**
- **Verify `skillOverrides`' documentation status.** Two runs disagree. It is the only lever reaching
  claude.ai-synced skills, so its tier decides whether it can be recommended or only reported.

### Phase 1 — repo corrections (independent, shippable now)

Five corrections owed regardless of whether the plugin ships; each is small and separable. See
[FINDINGS.md](FINDINGS.md) "Corrections owed to this repository": the safe-mode clean-room claim, the
`unhobble` `CLAUDE_CODE_SIMPLE` gotcha, the stale permission-rule-hygiene citation plus its
tightening gap, the S7 coverage-matrix row this work closes, and the `discovery` preload bug.

### Phase 2 — measurement engine

Baseline capture, A/B differencing driver, version-aware parser with the four known parse traps
handled, binary pinning, graceful degradation. Ships with the ledger format.

### Phase 3 — lever catalogue

One entry per lever: detection, honesty category, official citation, scope, and the exact config it
would emit. Data, not prose — so a new lever is a row, not a rewrite.

### Phase 4 — the report

Ranked attribution, category totals, and the honesty categories. Read-only. This is the default
action and the durable asset.

### Phase 5 — the guided fix path

Interactive walkthrough behind an explicit override, the `ask` hook, scope-differentiated write
posture, and the before/after ledger entry.

### Phase 6 — evals and the acceptance gate

Per the marketplace's standing rule that evals outlive instructions — they are what makes the next
deletion round provable.

## Related

- Research artifacts: `.work/startup-context-baseline/` (nine run slices, `INDEX.md`,
  `MEASUREMENTS.md`, `source-levers.md`, `DESIGN-PRINCIPLES.md`, interview ledger)
- [FINDINGS.md](FINDINGS.md) — evidence, provenance tiers, per-lever dispositions
