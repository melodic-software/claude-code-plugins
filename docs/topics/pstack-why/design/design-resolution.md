---
topic: pstack-why
outcome: early-exit
tier: B
date: 2026-08-19
---

# Design resolution — `/discovery:trace-intent`

**Outcome: early-exit.** No separate `/planning:design` pass is run, because every thread a design
pass would open was already driven to a resolution by the four stages that ran ahead of it, each
leaving a durable artifact. This file records where each thread landed and who resolved it, so the
gate is satisfied by evidence rather than by ceremony.

Tier B rather than C: the change introduces one genuinely new contract (a third sidecar header
schema) and touches more than five files. Tier A is not claimed — there is no new module, no package
topology change, and no data-model change; the new skill slots into an existing plugin whose
architecture is fixed and documented.

## Where each design thread was resolved

| Thread | Resolution | Resolved by |
|---|---|---|
| Capability boundary | Evidence substrate *outside* the repo; git archaeology delegates to `/discovery:explore git` | Interview Q8, after 3 validators challenged the placement |
| Naming | `/discovery:trace-intent`; no philosophy exception entry | Interview Q9 (reclassified to the user by all 3 validators) |
| Evidence-category set | Three live, all presence-gated, none guaranteed, plus a provider-adapter seam | Interview Q10, after a repo sweep found four categories with zero representation |
| Confidence contract | Five-tier **intent-evidence** axis + a non-routing source-reliability note | Interview Q7 → amended by research (ICD 203 label conflation; missing reliability dimension) |
| Code-shape exclusion | Absolute, argued operationally; recorded as a deliberate departure from upstream | Brief constraint 3 → sharpened by research (upstream permits it at `Inferred`) |
| Artifact shape | Index-plus-sidecar, `INTENT.md` + `INTENT-<section>.md`, private (not a lifecycle kind) | Interview Q11 + explore's artifact-shape sidecar |
| Dispatch shape | One purpose-built agent, `researcher` pattern (`disallowedTools:` denylist) | Explore — an allowlist strips every MCP tool, fatal for a tracker/forge-reaching skill |
| Cross-plugin seam | Additive-only edit to `reason-dont-recite`, forced by `skill-quality` check 3 | Explore + the audit's CI-gate finding |
| Fresh-eyes posture | Form-1 declaration, backtick-free, adjacent to the gate | Explore's fresh-eyes sidecar |

## The one new contract — a type sketch

The third sidecar header schema. Modelled on the two existing ones and deliberately not either of
them: research evidence carries a URL, a tier and a publishing pool; exploration evidence carries a
repo path and `verified: read | grep | inferred`; intent evidence carries neither shape.

```yaml
topic: <slug>
section: <stable-id>
abstract: <one line, copied verbatim into the index>
question: <the why-question this section answers>
claims:
  - claim: <the reconstructed intent>
    tier: Direct | Supported | Inferred | Speculative | Unknown
    sources:
      - ref: <commit sha | PR #N | ticket id | doc url | file:line>
        kind: <evidence category that produced it>
        reliability: <author proximity to the decision; staleness>
```

Two properties are load-bearing and are the reason this is a contract rather than prose:

- **`tier` is readable off the header**, so a verifier can grade tier assignment mechanically —
  the same property `verified:` and `sources[]` buy for the sibling families.
- **`reliability` is a sibling of `ref`, not of `tier`.** Every comparator scheme (ICD 203, GRADE,
  Admiralty AJP-2.1) separates evidence directness from source reliability and forbids merging
  them. Only `tier` routes to an output section; `reliability` annotates and never routes.

## What an early-exit gives up, stated plainly

A `/planning:design` pass would have explored alternative shapes for the header schema itself
(a flat per-claim table, a separate reliability ladder, no per-claim structure at all). That
exploration did not happen. The schema above is the first shape that satisfies both load-bearing
properties, not the winner of a comparison. If it proves awkward during implementation, that is the
expected failure mode and the correct response is to reopen it here rather than to bend the
implementation around it.
