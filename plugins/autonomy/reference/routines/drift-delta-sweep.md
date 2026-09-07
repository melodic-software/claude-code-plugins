# Drift-delta sweep

Normative leaf of the [routine catalog](../routines.md): the `drift-delta-sweep` v1 class
definition — a standing sweep that runs the repository's installed drift lanes on a cadence
and reports what moved since the previous cycle.

## Purpose

The toil addressed is a coverage gap rather than a detection gap. The drift lanes a
repository already installs are read-only and cheap to run, but they run only when a human
remembers to invoke them, so movement between one invocation and the next is noticed late or
not at all. `drift-delta-sweep` runs those lanes on a cadence and reports their movement, so
drift coverage is a standing property of the repository rather than a habit somebody has to
keep.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **weekly** — an org-bindable value set in the org's routine
binding, never contract-fixed.

The run predicate is a fact of the class, not a requirement the class imposes on a binding.
The two delta lanes compare against their previous cycle, and capture a comparison point for
the next one, only when the executing session resolves a **branch identity** — a branch
checkout, or a logical ref the runner supplies — and finds its memory-tier home
**persisted across** runs. A run that resolves neither still executes and still reports: it
compares nothing, captures nothing, and says so.

One illustrative binding, not a fixed requirement: a scheduled job on the org's
CI-orchestration home, whose runner restores that home and checks out the branch before the
run, which guided setup records as the `ci-cron` scheduler class.
No vendor scheduling surface is named here; guided setup researches scheduling surfaces live.

## Access scope

Repo — the sweep reads the repository tree and writes through the governed queue and tracker
only. No merge path: the repository drift audit lane runs without `--fix`, and no lane in the
fan-out prepares or applies a repository change. No production, product, org, or external-web
access, so the connector-prerequisite branch of the mapping rules never applies. Per the
catalog mapping rules' access axis, repo scope sets the `L2` unattended floor as the class
prerequisite ([guardrail contract](../guardrails.md)).

## Output contract

- **Advisory report** — one report per run, carrying one section per lane, a **coverage line**
  naming which enforcement-surface layers and which audit dimension this cycle walked, and a
  "lanes not run" section naming each absent or blocked lane and why it did not run.
- **Work items** — filed through the governed queue for movement whose correction needs
  authorial judgment.

The report is also the evidence with which this class keeps its own place on the enforcement
surface. A catalog routine's handler runs no work itself and enqueues one signal onto a
tracker-held governed queue item, so the durable record of the class is that queue item — the
recurring-work-item shape the enforcement-surface lane's own guidance prefers — minted by a
scheduled tick. That queue item is itself an item on the enforcement surface, and the report
is what has to justify it.

## Fan-out

The class's instruction content: three lanes, invoked in this order. Each names the plugin
that owns it, is gated on that plugin's presence at the point of invocation, and states its
fallback in the same sentence.

1. **The instruction-placement delta lane.** Invoke `/instruction-placement:delta` when the
   `instruction-placement` plugin is installed; where it is absent, record the lane as not run
   and continue. The lane owns what moved in the instruction-placement findings since its own
   last run. Bootstrap rule: where the lane reports no prior artifact to compare against,
   invoke `/instruction-placement:audit` instead — read-only, its only write being its own
   findings artifact — so the next cycle has a baseline, and record the cycle as a bootstrap
   in the coverage line.

2. **The enforcement-surface delta lane.** Invoke `/overengineering:delta` with `unattended`
   and the cycle's two layers when the `overengineering` plugin is installed; where it is
   absent, record the lane as not run and continue. The lane owns what moved in the
   enforcement surface since its own last run. The layer pair rotates on the ISO week number,
   read with `date -u +%V`; the pair index is (ISO week − 1) mod 5:

   | Pair index | Layers |
   |---|---|
   | 0 | `agent-hooks agent-instructions` |
   | 1 | `repo-hooks vcs-hooks` |
   | 2 | `ci-lanes gate-scripts` |
   | 3 | `satellite-workflows branch-protection` |
   | 4 | `forge-apps external-integrations` |

   The rotation is stateless — a function of the week alone — so a 53-week year repeats one
   pair, which the coverage line records. The report carries the lane's own coverage line.

3. **The repository drift audit lane.** Invoke `/codebase-health:audit` without `--fix` and
   with exactly one dimension flag when the `codebase-health` plugin is installed; where it is
   absent, record the lane as not run and continue. The lane owns the full drift pass over
   documentation, configuration, code, and architecture claims; it is a full pass every cycle
   and never a delta. The dimension rotates on the same ISO week number; the dimension index
   is (ISO week − 1) mod 4:

   | Dimension index | Flag |
   |---|---|
   | 0 | `--docs-only` |
   | 1 | `--config-only` |
   | 2 | `--code-only` |
   | 3 | `--arch-only` |

   Before invoking, read the lane's own tracked configuration and expand that dimension's
   `primary-sources` globs. Where the configuration resolves no targets for the dimension, or
   the expanded list exceeds twenty files — the lane's confirm threshold, which an unattended
   session cannot answer — do not invoke the lane, and record it as not run with the dimension
   and the file count. Keep the lane's checklist in-response and take no persist offer.

## Derived guardrail row

The row is derived through the catalog's mapping rules, never hand-assigned:

1. **Judgment axis.** Which movement matters, and which of it needs authorial judgment, is
   semantic judgment no rule engine resolves — agent judgment (`AGT`). Detection belongs to
   the lanes; the sweep's judgment is over what they returned.
2. **Output axes.** The advisory report derives `C1` through the `AGT` + report rule, and the
   filed work items derive `C1` through the `AGT` + work-item rule: governed-queue and tracker
   writes with no repository mutation, scoped as permitted `C1` output by the
   [work-classes leaf](../guardrails/work-classes.md).
3. **Risk-raising axes.** No portion of the class makes a direct change, so no structural or
   configuration surface is the target of one and the `C4` axis does not fire. Access is
   `repo` and every input is repository content the org already governs, so the
   input-provenance axis does not fire and the class is not `C5`.
4. **Access axis → prerequisite.** Repo scope sets the `L2` unattended floor as the dispatch
   prerequisite; the `C1` matrix row keeps the floor at `L2`.

Derived row: `C1`, with the `L2` unattended floor — in the
[guardrail matrix](../guardrails.md).

## Prerequisites

Per-identity needs under
[routine prerequisite resolution](../prerequisite-resolution.md). Axes derive through the
catalog mapping rules; the isolation floor and `executor_class` merge cap are cited from the
guardrail slice, never re-derived. Resolution verdicts use `supported` | `conditional` |
`unsupported` | `unknown`.

Single-posture identity: `drift-delta-sweep` (bare class token). The class has one output
shape, so no posture-qualified identity is minted.

| Axis | Value |
|---|---|
| Access class | `repo` |
| Isolation floor | `L2` — cited from the [matrix](../guardrails.md#the-matrix) `C1` row and the [unattended floor](../guardrails/isolation-ladder.md#unattended-floor) |
| Connector entitlements | none — `repo` access; the connector branch of [Access to prerequisites](../routines.md#access-to-prerequisites) does not apply |
| Connector entitlement rung | n/a (no connector). For `prod` / `product` / `org` / `ext`, entitlement binds at the [Org binding layer](../binding-seam.md#resolution-ladder) |
| `executor_class` merge cap | cited from [executor surface classes](../trigger-dispatch.md#executor-surface-classes) — security-binding `executor_class`; `vendor-hosted` caps every class at human-gated merge; never repo-derivable. Merge policy for this identity is n/a (`C1`) |
| Repo needs | repository source tree; documentation corpus; tracker binding when filing work items through the work-item tracker seam. The class's substantive prerequisites, three optional sibling plugins present and a run that resolves a branch identity and persists its memory-tier home, are not representable in the generated emission |

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern at class level is the operator-run cadence pass over report-only
drift detectors: report-only drift-watch rows already carried in a consumer's recurring
schedule, and the recurring-wiring guidance the enforcement-surface lane gives for its own
repeat runs. Said plainly: no run record exists yet for these three lanes together. The `v1`
status rests on the class-level pattern, not on a logged run of this fan-out.
