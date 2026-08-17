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
tools; it does not and structurally cannot itemise built-in tool schemas — the largest single
contributor, held as two lump-sum rows (18.1k prefix + 17.8k deferred = 35.9k here, against a 35.3k
headline that counts only the prefix row; the deferred pool is excluded from the context-usage
headline yet still ships in every request). A/B differencing against a fixed baseline is the only
route to per-tool numbers, and it is compositional.

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

### Phase 0 — resolve two blockers before building ✔ RESOLVED 2026-08-17

- **The Agent SDK exposes `getContextUsage()`** (`@anthropic-ai/claude-agent-sdk` 0.3.233,
  `SDKControlGetContextUsageResponse`, not marked experimental). Probed live against the v2.1.232
  binary: exact integers matching the CLI's `/context` output byte-for-token (System tools 18,131;
  deferred 17,835; Skills 9,937; agents 1,545), with `model`, per-MCP-tool, `memoryFiles`, and
  per-skill `skillFrontmatter` attribution. **However `systemTools`, `deferredBuiltinTools` and
  `systemPromptSections` are declared in the type but arrive unpopulated** — the same dead data path
  as the renderer's `systemToolDetails`. **Engine shape: SDK-primary hybrid.** `getContextUsage()`
  is the meter; A/B differencing (spawning via the SDK with varied `disallowedTools`) supplies
  per-built-in-tool attribution; the markdown parser survives only as a no-SDK fallback.
- **`skillOverrides` is documented** — a row in the official settings reference plus a full
  "Override skill visibility from settings" section on the skills page (both fetched raw 2026-08-17).
  The context-command run's "binary-only" claim was its own WebFetch-truncation trap. Recommendable,
  with the documented carve-out that it does **not** apply to plugin skills (those toggle via
  `enabledPlugins`). Same fetch surfaced two additional documented levers for the catalogue:
  `skillListingBudgetFraction` (the listing cap itself) and `skillListingMaxDescChars`
  (default 1536, the per-skill truncation the `< 20` rows reflect).

### Phase 1 — repo corrections (independent, shippable now)

Five corrections owed regardless of whether the plugin ships; each is small and separable. See
[FINDINGS.md](FINDINGS.md) "Corrections owed to this repository": the safe-mode clean-room claim, the
`unhobble` `CLAUDE_CODE_SIMPLE` gotcha, the stale permission-rule-hygiene citation plus its
tightening gap, the S7 coverage-matrix row this work closes, and the `discovery` preload bug.

### Phase 2 — measurement engine ✔ SHIPPED 2026-08-17 (`context-budget` 0.1.0)

Baseline capture, A/B differencing driver, version-aware parser with the four known parse traps
handled, binary pinning, graceful degradation. Ships with the ledger format.

Landed as `plugins/context-budget/` (manifest, README, CHANGELOG, `skills/audit/` with
`scripts/measure.mjs`, `reference/engine.md`, evals, hermetic tests; `lib/state-key.sh` adopted
from the shared cluster; registered in the marketplace, catalog, leaf-name registry, and
state-key sync). Verified live against the pinned v2.1.232 binary: sdk mode returns exact
integers, the per-tool deny deltas reproduce and pass the engine's additivity check, cli-parse
degrades with recorded caveats, and unparsable input exits 3 with a structured remediation.

### Phase 3 — lever catalogue ✔ SHIPPED 2026-08-17 (`context-budget` 0.2.0)

One entry per lever: detection, honesty category, official citation, scope, and the exact config it
would emit. Data, not prose — so a new lever is a row, not a rewrite.

Landed as `skills/audit/reference/levers.json` (19 rows covering L1–L9/L11 plus the deferral
dual-ledger row and the vendor-weight floor; L10/L12 are route-outs in the catalogue meta), with
`levers.test.sh` making the honesty rules mechanical — vocabulary-confined categories, mandatory
citations/postures/verified dates/recheck triggers, net-negative and unverified rows barred from
the recommendable posture, and a no-shipped-token-figures scan (which caught and removed one
violation during authoring). SKILL.md gained the lever-presentation step wiring conditions-resolved-
by-measurement and the dual-ledger rule into the workflow.

### Phase 4 — the report ✔ SHIPPED 2026-08-17 (`context-budget` 0.3.0)

Ranked attribution, category totals, and the honesty categories. Read-only. This is the default
action and the durable asset.

Landed as `skills/audit/reference/report.md` (the report contract: stamp, smart-zone headline
with the dual-ledger sentence, measured category totals, ranked attribution with
incomparable-rows-carry-reasons and unmeasured-tools-listed rules, lever findings grouped by
honesty category, route-outs, degradations; persisted one-file-per-run) plus the SKILL.md report
step. Zone framing composes with `context-guard` presence-gated.

### Phase 5 — the guided fix path ✔ SHIPPED 2026-08-17 (`context-budget` 0.4.0)

Interactive walkthrough behind an explicit override, the `ask` hook, scope-differentiated write
posture, and the before/after ledger entry.

Landed as the SKILL.md fix-path section (explicit `fix` argument only; recommendable-on-fit rows
with measurement-resolved conditions; one-lever-at-a-time apply → re-measure → compare → ledger)
plus `hooks/settings-write-ask.mjs` (PreToolUse `permissionDecision: "ask"` on settings-surface
writes, exec-form `node`, fail-open, `settings_write_ask_enabled` userConfig kill switch, tested).
The checkpoint-not-guarantee caveats (PermissionRequest, `disableAllHooks`, undocumented
`bypassPermissions` interaction) are stated in the hook, the skill, and the README. Wizard-UX
detail (Q15) resolved as: ranked-report order, per-lever approval, no free-form branching.

### Phase 6 — evals and the acceptance gate ◐ IN PROGRESS 2026-08-17 (`context-budget` 0.5.0)

Per the marketplace's standing rule that evals outlive instructions — they are what makes the next
deletion round provable.

Nine eval cases ship (measurement honesty, degradation, dual-ledger, incomparable rows,
print-never-apply, /doctor routing, and three fix-path cases), passing the evals-quality gate
with zero warnings. Mechanical acceptance sweeps recorded: zero research-figure hits in the
shipped plugin, catalogue and hook contract tests green, skill-layout gate zero errors, live
engine verification (exact integers, reproduced per-tool deltas, additivity check) done during
Phase 2. A fresh-context acceptance verifier over criteria 1–6 was dispatched 2026-08-17; its
verdict and any resulting fixes land as the closing commit of this phase.

## Related

- Research artifacts: [research/](research/) — the nine run slices plus `INDEX.md`,
  `MEASUREMENTS.md`, `source-levers.md`, `DESIGN-PRINCIPLES.md`, and the interview ledger,
  promoted from the session-scoped `.work/startup-context-baseline/` memory slice on 2026-08-17
  because cloud containers are reclaimed and the citations feed Phase 3
- [FINDINGS.md](FINDINGS.md) — evidence, provenance tiers, per-lever dispositions
