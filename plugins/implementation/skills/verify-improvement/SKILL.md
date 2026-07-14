---
name: verify-improvement
description: "Verify a measurable-improvement claim against a baseline captured BEFORE the change — two metric families (`performance`: wall time, memory, allocations, throughput, latency; `metrics`: complexity, coverage, coupling), each with a `baseline` phase at planning time and a `compare` phase after the change. Never claims improvement without a baseline (no baseline → honest 'cannot quantify'); use for 'is it faster', 'before/after', 'prove the improvement', while intent/outcome confirmation stays with /verify-changes."
user-invocable: true
argument-hint: "[performance|metrics] [baseline|compare] [--artifacts-dir <dir>] [--topic <slug>]"
disable-model-invocation: false
---

## Purpose

Artifact protocol: read `${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`; remove its two optional
flags from `$ARGUMENTS` before interpreting the metric family and phase.

`/verify-improvement` answers **"did the claimed improvement actually happen, by how much?"** — it MEASURES a delta (before → after) against a baseline captured before the change. It is the measurable-delta twin of `/verify-changes` (which confirms intent/outcome) and is distinct from a review gate (which reviews design quality for ship-readiness on an absolute axis).

Core rule: **never claim improvement without a baseline captured before the change.** If no baseline exists, report honestly — "Baseline not captured. Current measurement: X. Cannot quantify improvement." — and never fabricate a delta.

## Two-phase model

The measurement mechanism is SSOT here; the planning stage *routes* to it when a plan states a measurable goal, `/verify-changes` *redirects* improvement claims to it.

| Phase | Stage | Who invokes | What it does |
|-------|-------|-------------|--------------|
| `baseline` | planning time (plan states a measurable goal) | `/verify-improvement <family> baseline` | Capture pre-change measurements → store under `<plan-artifact-dir>/baselines/` + record baseline + target in the plan |
| `compare` | after the change (default phase) | `/verify-improvement <family>` | Re-measure under the same conditions → compare to the stored baseline → verify the claim |

Baseline storage: under protocol-resolved `<topic-root>/baselines/`, beside the change's plan artifact.

**Measurement tooling:** use whatever harness the consuming project wires (BenchmarkDotNet, pytest-benchmark, a metrics collector); when none exists, run both phases manually per the context-file discipline — do not add a harness speculatively.

## Mode dispatch

Parse `$ARGUMENTS` for a metric family first, then a phase (`baseline` / `compare`; default `compare`).

| Signal | Family | Read |
|--------|--------|------|
| `performance`, "is it faster", "before/after" runtime numbers, memory / allocations / throughput / latency | **performance** | [context/performance.md](context/performance.md) |
| `metrics`, "is it simpler/cleaner", complexity / coverage / CRAP / coupling / duplication | **metrics** | [context/metrics.md](context/metrics.md) |

No family argument → infer from the claim: runtime-resource claims → `performance`; code-shape claims → `metrics`. If the claim is ambiguous ("more efficient"), ask which resource before measuring.

Each context file owns its family's full discipline: claim-to-metric mapping, measurement methodology, report template, verdict vocabulary, and pitfalls.

## Prerequisite — green mechanical state (both phases)

Measuring broken code is meaningless, and a baseline captured on a broken tree poisons every later comparison. Before EITHER phase — `baseline` capture or `compare` — confirm the mechanical pass is green: reuse a `/build` or `/verify-changes` Stage-1 result from this conversation if nothing changed since; otherwise invoke `/build`. Do not reimplement build/test/lint here.

## Integration

| Condition | Action |
|-----------|--------|
| An approved plan states a measurable goal | Run the `baseline` phase BEFORE implementation |
| Improvement claimed without data (in `/verify-changes`, review, or conversation) | Redirect here — `performance` or `metrics` per the claim |
| Verdict is DEGRADED or NOT CONFIRMED | Surface immediately; the claim does not hold — fix or withdraw it |
| Measurement complete | Feed the comparison table into the `/verify-changes` outcome report or PR evidence |

## What this skill does NOT do

- **Does not confirm intent/outcome** — "did we build the right thing" is `/verify-changes` (`outcome` / `fix` / `refactor` criteria).
- **Does not review for ship-readiness** — that's the project's review gate; the measure-delta vs review-for-ship boundary is stated in "Purpose" above.
- **Does not capture baselines after the fact** — a post-change "baseline" is not a baseline. Missing baseline → honest "cannot quantify", plus a current-state measurement for the record.
- **Does not run the mechanical pass** — `/build` owns build+test+lint; this skill only requires its result to be green.

## Gotchas

- **Baseline BEFORE the change, compared under the SAME conditions after.** Condition drift invalidates the comparison — the run/warm-up/conditions methodology is owned by [context/performance.md](context/performance.md).
- **Noise floor first.** If the projected saving sits within run-to-run variance, the change is unmeasurable — surface that before the work, not after (detail: [context/performance.md](context/performance.md)).
- **Never fabricate numbers.** No baseline, high variance, or differing conditions → INCONCLUSIVE / NOT CONFIRMED, stated plainly.
