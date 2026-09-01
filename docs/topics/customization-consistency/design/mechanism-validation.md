# Blind validation tally — retired-convention mechanism candidates

Date: 2026-09-01. Three independent fresh-context validators, blind to authorship and design
rationale, ranked candidates A/B/C against weighted criteria (Brief fit > drift resistance >
simplicity/total cost > failure modes > rollout value) and spot-verified every load-bearing repo
claim.

## Tally

| Validator | 1st | 2nd | 3rd |
|---|---|---|---|
| 1 | B | C | A |
| 2 | B | C | A |
| 3 | B | A | C |

**Winner: Candidate B — unanimous first place.** Per-plugin `retirements.yaml` (append-only,
flat-YAML subset, CI schema-validated) + one shared deterministic helper `lib/check-retirements.sh`
synced byte-identical via the existing state-key.sh sync-and-registry mechanism. Detection = fixed
step in setup `check` (TSV findings, loud failure on bad records); cleanup = per-item gated in
`apply`; judgment-bearing migrate content stays with the model per the record's successor prose.

## Fact-check results

No false repo claims in any candidate. Two inexact claims:
- B lumps `parse-concern-value.sh` into the sync precedent (not synced/registered; precedent
  survives on state-key.sh alone).
- C claims "51 setups need no individual edits" (consolidated paragraph spans ~25 skills; plugins
  ship independently).

## Named weaknesses of the winner

- Bash runtime dependency on a Windows-heavy fleet — mitigated by degraded-visible UNKNOWN (never
  silently green), but the sweep can be chronically degraded in PowerShell-only environments.
- No coverage for leftovers whose owning plugin was uninstalled, or whose setup is never re-run
  (context-guard's documented death spiral) — the one structural gap C exposes.

## Hybrid recommendation (all three validators converge)

Ship B as the base, plus:
1. **A's per-retirement eval-case requirement** — one eval per record (detect-hit + clean path);
   minutes of authoring cost, covers the semantic-probe-quality gap.
2. **Runtime fleet sweep, not CI aggregate** (validator 1's refinement): a claude-config audit-pass
   lane that globs installed plugins' `retirements.yaml` at runtime — no generator, no committed
   registry — covers the "updated but never re-setup" case immediately.
3. **Defer C's full CI-aggregated registry** (the only way to cover uninstalled plugins) until
   orphan leftovers prove real in practice.
4. C's archived/report-only demotion field for old records instead of indefinite full-severity
   retention.

Status: awaiting user approval (Brief deferred question Q9, arbiter USER-RESERVED).
