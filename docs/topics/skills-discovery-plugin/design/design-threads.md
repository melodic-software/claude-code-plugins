# Design threads — audit-skill-starvation

Scope: `module`. Tier A. Brief: [`../PLAN.md`](../PLAN.md) (locked + verification-corrected).
Status vocabulary: **resolved** (decided) / **directional** (direction agreed, detail deferred) /
**open** (needs the user) / **deferred** (needs research or a later gate).

## T1 — Source strategy: is the OTEL collector required? (Brief Q16) — OPEN

`claude_code.skill_activated` is the only source carrying `invocation_trigger`, and that attribute
is what separates *Claude never picks this* from *I never run this*. But it needs a running
collector, and un-redacted third-party skill names additionally need `OTEL_LOG_TOOL_DETAILS=1`,
which widens collection to tool arguments and error strings.

| Option | Consequence |
|---|---|
| (a) OTEL required | Sharpest classification; unusable for any operator without a collector |
| (b) **OTEL optional, declared capability tiers** | Runs everywhere; the report states which tier it ran at and which claims that tier can support |
| (c) JSONL only | No collector dependency, but forfeits `invocation_trigger` entirely |

**Recommendation: (b), with the tiers named in the contract.** The Brief already commits to
declaring coverage honestly, so a capability tier is the same idea applied to sources rather than to
time. Tiers: **T-full** (OTEL present → trigger attribution available), **T-local** (JSONL only →
tool-vs-expansion split, no proactive-vs-nested distinction), **T-baseline** (native counters only →
lifetime totals, no windowing). A claim is rendered only at a tier that supports it.

## T2 — Starvation cutoff: how is "starved" computed? (Brief Q17) — OPEN

The scorer `usageCount × max(0.5^(days/7), 0.1)` is confirmed in the v2.1.232 bundle but is
undocumented and unversioned. The verifier's steer was: do not reimplement it.

**Recommendation: split the claim into a certain half and an inferential half — they are different
claims and deserve different confidence.**

- **Certain (documented inputs only):** whether the listing is overflowing AT ALL, and by how much.
  Budget = `skillListingBudgetFraction` × context window × 4 bytes/token (all documented, all
  readable), and the demand side is the sum of each skill's `description` + `when_to_use`, capped at
  `skillListingMaxDescChars` — readable from frontmatter. If demand > budget, **truncation is
  provably happening**, and the overflow magnitude is arithmetic. This is the headline finding and
  it needs no undocumented constant.
- **Inferential (labeled as such):** WHICH specific skills lose their descriptions. That ordering is
  the undocumented scorer. Render it as a ranked *likelihood band* ("most likely starved" →
  "least"), never as a hard cutoff line, and never present the ranking as exact.
- **Exemptions applied first:** bundled prompt skills never compete, and `name-only` overrides are
  pre-excluded with their bytes NOT returned to the pool. Both are excluded from the demand sum and
  from the ranking, or the arithmetic is wrong.

This also degrades correctly: the certain half holds at every capability tier from T1.

## T3 — Reach state: one taxonomy or two orthogonal axes? — OPEN

The Brief says every skill resolves to exactly one reach state. Modeling that as a single flat enum
collapses two genuinely independent questions.

**Recommendation: two orthogonal axes, rendered as one cell.**

- **Reachability (structural):** can the model ever select this skill? — `model-reachable` /
  `user-only` (`disable-model-invocation`, 59 of 213 locally) / `hidden` (`skillOverrides: off`,
  plugin disabled) / `misconfigured` (the 11 silent causes) / `exempt` (bundled, name-only).
- **Observation (temporal):** what have we actually seen? — `active` / `cooling` / `dormant` /
  `no-observation-in-horizon` / `not-observable` (below the exposure floor).

The action differs per combination, which is the point. A `model-reachable` skill with no
observation is a starvation candidate. A `misconfigured` one with no observation is a *fix-me*,
never a delete-me. A `user-only` one with no observation is simply a skill you type rather than one
Claude picks. A single flat enum forces all three into one bucket and reproduces the libel the audit
exists to prevent.

## T4 — The inventory→usage join — RESOLVED (directional detail below)

Usage keys are `<plugin>:<leaf>`; inventory emits bare leaves nested under
`disk.installed_plugins[<marketplace>][<plugin>].components.skills[]`. Synthesize the qualified name
from the enclosing dict keys. Where two marketplaces ship a same-named plugin, the usage key is
ambiguous: **mark the row `ambiguous-attribution` and report it, never silently pick one.**
Native `skillUsage` additionally falls back qualified→bare, so check both keys before calling a
counter zero.

## T5 — Honesty floor: per-source horizons — RESOLVED

Each source has its own horizon: OTEL = earliest retained event; JSONL = earliest row; native =
`firstStartTime`. **Each claim is gated by the horizon of the source backing it** rather than by one
global horizon, because native reaches back further (lifetime) than the JSONL store. The report
prints every horizon it used. Exposure floor (30 days since created, 7 days inactive) suppresses
cold verdicts below threshold.

## T6 — Module boundary and ownership — RESOLVED

New skill owns *interpretation*; `observability` keeps hook-events, OTEL infrastructure, and the one
retention harness. `read-routing.md` gains a routing row. `clean.sh` gains the skill-usage target
via the hooks' path policy (all three scopes). No hook changes. `claude-ops` gains its first `lib/`
for `state-key.sh`.

## T7 — Report contract (JSON) — DIRECTIONAL

Keyed per `plugin-data-report-keying` Rule 1; one file per run plus an appended history line; never
a rolling `latest.json`. Schema carries: run metadata (tier from T1, per-source horizons from T5,
budget arithmetic from T2-certain), then one row per skill with both T3 axes, the evidence backing
each, and an explicit `confidence` on any inferential field. Versioned with a `schema_version`,
additive-only, per the marketplace's existing envelope discipline.

## T8 — Test seams — DIRECTIONAL

Highest-value seam is a **pure classifier**: `(denominator, events, config, clock) → report model`,
exercised with fixtures for the failure modes the audit found — empty store, horizon shorter than
the tier windows, `pluginUsage` seeded rows, same-second duplicate invocations, cross-marketplace
name collision, bundled-exempt skills, over-budget and under-budget listings. Injecting the clock is
what makes horizon and tier behavior testable at all. Shell-level `*.test.sh` per repo convention
covers the CLI surface. Aim for the fewest seams that cover the surface.

## T9 — Design defaults — DIRECTIONAL

- **Configurability:** windows and the exposure floor must be tunable, but `CLAUDE_PLUGIN_OPTION_*`
  cannot reach a skill's Bash script (proven by the repo's own smoke tests) — so config arrives via
  `${user_config.KEY}` substitution into SKILL.md or explicit flags. Design for flags.
- **Extension:** the source ladder is the extension axis — a new source implements the same
  `(events, horizon, capabilities)` shape and slots into the tier logic.
- **Observability:** the skill is itself a read-only reporter; it emits no telemetry of its own
  (adding a hook would violate the hook budget the Brief already respects).
- **Testability:** driven by T8's injected clock and pure classifier.

## Dependency order

T1 gates T2's tier degradation and T7's run metadata. T3 gates T7's row schema and T8's fixtures.
T4, T5, T6 are independent and already resolved. Q18 (session transcripts) stays **USER-RESERVED**
and is untouched here — it surfaces at the plan approval gate with plan-time context.
