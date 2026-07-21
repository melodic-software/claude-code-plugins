# Security review

Normative policy contract for the security-review layers of the
[guardrail matrix](../guardrails.md)'s verification column. The matrix assigns each work class (`C1`–`C5`) a verification cell;
this leaf defines the two security-review layers those cells compose, the per-layer
blocking knob, and the cost posture. Which scanner or reviewer instances exist is an
org-binding outcome; this contract fixes the layer classes, knob semantics, and shipped
defaults.

## Two layers

| Layer | Class | Adjudication |
|---|---|---|
| 1 | Deterministic scanners | Machine-adjudicated: same input, same verdict |
| 2 | AI security review | Model-adjudicated: judgment findings over the change |

**Layer 1 — deterministic scanners.** Scanner CLASSES, instances org-bound: secret
detection, dependency vulnerability audit, static analysis. Deterministic verdicts make
this layer safe to run blocking wherever the matrix requires it.

**Layer 2 — AI security review.** A model-driven security review of the change: logic
flaws, injection paths, privilege and trust-boundary errors — findings deterministic
scanners cannot express. Verdicts are judgment, so the layer ships advisory wherever the
matrix has not yet earned blocking (promotion discipline below).

## Per-layer blocking knob

Every layer × class cell carries one knob: `advisory` | `blocking`.

- `blocking` — a failing verdict is a gate failure: the change does not merge, and the
  failure raises the matrix's gate-failure escalation event class.
- `advisory` — findings are recorded on the item's verification record and surfaced to
  the human merge gate; they never block on their own.

That a failing verdict can gate the merge at all is this contract's own instantiation: the
Boris playbook keeps automated review a default feeding a human merge, never a gate, so the
`blocking` knob layers a gate onto that advisory posture rather than inheriting it.

Knobs are security-sensitive and bind ONLY on the org's security governance surface (the
settings-as-code home, outside the blast radius of the agents they govern — an
agent-writable blocking knob is a bypass channel). Shipped defaults:

| Class | Layer 1 (deterministic scanners) | Layer 2 (AI security review) |
|---|---|---|
| `C1` | n/a — no repo mutation to scan; output-shape checks govern | n/a |
| `C2` | `blocking` | not required; `advisory` where org-enabled |
| `C3` | `blocking` | `advisory`, promotable to `blocking` |
| `C4` | `blocking` | `blocking`; human review additionally mandatory per the matrix |
| `C5` | `blocking` | `blocking`; full-gate cell — the zero-secret-exposure execution constraint is owned by the [isolation floor](isolation-ladder.md), not this leaf |

Shipped defaults are FLOORS: a binding may tighten any cell (`advisory` → `blocking`) but
never weaken one below its shipped default — a binding that tries is invalid. An absent
or invalid binding fail-closes: every knob resolves to its shipped default and every
promoted posture is unavailable. No silent degrade on any path.

Knob flips follow the matrix promotion discipline: `advisory` → `blocking` is a
human-ratified knob flip, recorded as a reviewable change on the governance surface and
earned on an evidence predicate over queryable verification telemetry; demotion on
contrary evidence is automatic and fail-closed, re-earned from there. The near-term
promotable cell is `C3` Layer 2; per-cell triggers and suggested default predicates live
in the [per-class detail leaf](work-classes.md).

## Cost posture

- The DEFAULT path is free: Layer 1's blocking obligations are satisfied by free-path
  scanner classes with zero paid dependencies.
- Entitlement-gated tools — paid code-scanning SKUs — are `advisory` + explicit opt-in,
  with the cost surfaced at opt-in time. They never hold a blocking cell's obligation,
  and an entitlement gap routes the tool to the advisory path rather than silently
  passing the layer.

## Setup and audit

The guardrail slice of guided setup configures this policy; no separate security-review
setup capability exists (near-duplicate ban). Setup always detect-diff-reconciles against
the org's EXISTING review surfaces — scanner configuration, review workflows, branch
protections — never greenfield-assumes and never silently overwrites; the same
detect-diff-reconcile obligation generalizes matrix-wide.
