# Work classes

Normative leaf of the [guardrail contract](../guardrails.md): the per-class risk-property
bundles behind the matrix rows, and the promotion/demotion discipline for its promotable
cells.

## Risk-property bundles

Each class is a bundle of four risk properties: blast radius, reversibility, input
provenance, and verifiability. The bundle — not the task's surface description — is what
assigns a class.

### `C1` — read-only

Audits, research, reports. "Read-only" scopes REPOSITORY surfaces: a `C1` run performs no
repository mutation. Writes to the governed queue and tracker — work-item filing, queue
comments, audit-trail artifacts — are PERMITTED: they are the class's output channel and land
on the queue's audit trail, not in the repository. Blast radius is informational only, and
there is nothing to revert; but the exfiltration surface remains, which is why the
min-isolation floor is `L2`, not `L0`. Verifiability is output-shape checking.

### `C2` — mechanical maintenance

Dependency bumps, lint/format, sync. Deterministic and trivially reversible; input
provenance is the org's own automation; verifiability is complete — deterministic blocking
gates decide the outcome without judgment.

### `C3` — scoped change

A briefed fix or small feature. Blast radius is bounded by the brief; tests exist, so
reversal is a bounded revert; verifiability combines deterministic gates with AI review.

### `C4` — structural

Refactors, migrations, contract changes. Blast radius is cross-cutting and reversal is hard,
so human review and human merge are mandatory, always, and the class escalates for upfront
plan approval before execution.

### `C5` — untrusted-provenance

Fork PRs, external contributions, unvetted repositories. The input provenance itself is
untrusted, and it dominates every other property. The class's min-isolation cell, `L3`, is
the floor the runner design pack's `C5`-dispatch gate cites: no `C5` item is dispatched onto
any execution surface below `L3`, and the class's merge policy never promotes.

## Promotion and demotion

This promotion apparatus — numeric predicate, human-ratified flip, automatic fail-closed
demotion — is this contract's quantification of the Boris playbook's qualitative bar that no
autonomy scales before the loop has "earned widespread trust": the trust requirement is the
playbook's, the evidence predicate over telemetry that measures it is this contract's.

Every promotable matrix cell carries a per-cell promotion trigger with one contract-fixed
shape: an **evidence predicate over queryable telemetry** — verification outcomes recorded
per the [telemetry contract](../telemetry.md) are the evidence base.

- **Promotion is a human-ratified knob flip — never automatic.** A satisfied predicate makes
  the cell ELIGIBLE; a human ratifies the flip, and the flip is recorded as a reviewable
  change on the governance surface.
- **Demotion is automatic and fail-closed.** Contrary evidence lowers the cell's effective
  state immediately, without waiting for human action; the cell re-earns promotion from
  there through the same evidence predicate.

## Suggested default predicates

The predicate shape is contract-fixed; the threshold values below are suggested defaults the
org binds (org-bindable values):

| Cell | Suggested default predicate |
|---|---|
| `C2` auto-merge | ≥ 20 autonomous C2 completions over ≥ 14 days with 100% deterministic-gate pass and 0 human-reverted merges |
| `C3` AI review advisory → blocking | ≥ 30 advisory reviews with 0 human-confirmed missed-blocking findings |
| `C4` / `C5` merge | never promotes — human merge always; no evidence predicate exists for these cells |

**Demotion evidence set** (one event suffices): any post-merge gate failure, any
human-reverted merge, any verification divergence.
