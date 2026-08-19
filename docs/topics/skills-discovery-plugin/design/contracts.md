# Contracts — audit-skill-starvation

Type model and output contract. Resolves T1, T2, T3, T7 from
[`design-threads.md`](design-threads.md).

## Refinement found during type modeling

`exempt` was listed as a *reachability* value in T3. That is wrong: a bundled prompt skill is fully
model-reachable — it is merely exempt from the description contest. Exemption is a property of
**starvation eligibility**, not of reachability. Modeling it as a reach state would have made every
bundled skill look unreachable.

So the row carries **three independent fields**, not two:

| Field | Question it answers |
|---|---|
| `reachability` | Can the model ever select this skill? |
| `observation` | What have we actually seen, within a stated horizon? |
| `starvation` | Is it competing for description budget, and is it likely losing? |

## Field 1 — `reachability` (structural)

| Value | Meaning | Action implied |
|---|---|---|
| `model-reachable` | Description is in context; Claude can select it | none — eligible for starvation analysis |
| `user-only` | `disable-model-invocation: true` (59 of 213 locally) | none — you type it; absence of model use is expected |
| `hidden` | `skillOverrides: "off"`, or its plugin is not enabled | enable it, or accept |
| `misconfigured` | one of the 11 evidenced silent causes | **fix** — never "delete" |
| `unknown` | reachability could not be determined | report as unknown, never infer |

`misconfigured` sub-causes are carried as a list, each with its evidence, because the remedies
differ: malformed frontmatter YAML, missing `description`, a synced-skill name collision, a
dot-prefixed directory, and so on. Provenance is stated at render time — these are assembled from
scattered docs plus binary strings, **not** an official list.

## Field 2 — `observation` (temporal, always horizon-qualified)

| Value | Meaning |
|---|---|
| `active` | invoked within the active window |
| `cooling` | last invoked between the active and dormant windows |
| `dormant` | has history, nothing within the dormant window |
| `no-observation-in-horizon` | sources cover this skill, and recorded nothing |
| `not-observable` | below the exposure floor, or no source covers it — **no verdict** |

Every rendered value carries the horizon and source that back it. A window wider than its source's
horizon is never rendered — it degrades to `not-observable`. `not-observable` is the default when
in doubt; it is what stops "never observed" from being reported as "never used".

## Field 3 — `starvation` (budget competition)

```text
eligibility : competing | exempt-bundled | exempt-name-only
verdict     : listing-fits | likely-starved | likely-retained | not-assessable
confidence  : certain | inferential
band        : 1..N rank within the competing set   (inferential only)
```

Per T2 the claim is split by confidence, and the two halves are computed separately:

- **`certain`** — whether the listing overflows at all, and by how much. Budget =
  `skillListingBudgetFraction` (default 0.01) × context window × 4 bytes/token, with
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` overriding unconditionally. Demand = Σ (`description` +
  `when_to_use`, each capped at `skillListingMaxDescChars`, default 1,536) over the **competing set
  only**. Exempt classes are excluded from the demand sum, and `name-only` freed bytes are NOT
  returned to the pool. If demand > budget, truncation is provably occurring: report the overflow
  magnitude and the approximate count running name-only. **This is the headline, and it needs no
  undocumented constant.**
- **`inferential`** — which specific skills lose their descriptions. Ranked by the observable proxy,
  rendered as a band, never as a hard cutoff, always labeled. Never presented as exact.

## Capability tiers (T1)

| Tier | Source | Adds | Cannot answer |
|---|---|---|---|
| `T-full` | `claude_code.skill_activated` | `invocation_trigger` → separates claude-proactive from user-slash from nested-skill | — |
| `T-local` | `skill-usage.jsonl` | tool-vs-expansion split, branch/project | proactive vs nested |
| `T-baseline` | native `skillUsage` | lifetime totals | any windowed claim; bursts (60 s debounce) |

A claim renders only at a tier that supports it. The run states its tier and why. Tiers are not
summed — the reconciliation rule from the Brief applies, and OTEL/local divergence is expected
(telemetry is not debounced; the native counter is), never reconciled away.

## Report schema (T7)

Keyed per `plugin-data-report-keying` Rule 1; one file per run plus an appended history line.
`schema_version` (SemVer), additive-only, consumers ignore unknown keys — matching the marketplace's
existing envelope discipline.

```jsonc
{
  "schema_version": "1.0.0",
  "generated_at": "<RFC3339 UTC>",
  "tier": "T-full | T-local | T-baseline",
  "sources": [ { "source": "otel|jsonl|native", "horizon_start": "<RFC3339>", "events": 0 } ],
  "listing": {
    "budget_chars": 0,          // computed, never hardcoded
    "budget_basis": "fraction|env-override",
    "demand_chars": 0,
    "overflow_chars": 0,        // > 0 proves truncation
    "competing_count": 0,
    "exempt_count": 0
  },
  "skills": [ {
    "qualified_name": "plugin:leaf",
    "attribution": "unambiguous | ambiguous-attribution",
    "reachability": { "value": "...", "causes": [], "evidence": [] },
    "observation":  { "value": "...", "horizon_start": "...", "backed_by": "otel|jsonl|native" },
    "starvation":   { "eligibility": "...", "verdict": "...", "confidence": "...", "band": null }
  } ],
  "withheld": [ { "claim": "...", "reason": "below exposure floor | horizon shorter than window" } ]
}
```

`withheld` is a first-class section, not an omission: the things the run **refused** to assert are
part of an honest report, and a consumer can see that a verdict was declined rather than missing.

## Terminology

| Term | Chosen | Rejected | Why |
|---|---|---|---|
| starved | `likely-starved` | "unused", "cold" | names the mechanism (budget suppression), not a usage tally |
| not observable | `not-observable` | "never used", "never" | the audit's central correction — absence of data is not absence of use |
| competing | `competing` | "eligible" | says what the skill is doing: contending for description budget |
| horizon | `horizon_start` | "since", "window" | distinct from the tier *windows*; a horizon bounds what CAN be known |
