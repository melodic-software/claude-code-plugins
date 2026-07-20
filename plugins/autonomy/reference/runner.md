# Runner

Design-pack hub for the autonomous-drain runner: the charter it graduates from, the
composition spine that shapes it, and the eight seams that are its interface set. This
document is the glance layer of a progressive-disclosure design pack — the charter, the spine
shape, and the seam list here answer "what is the runner, what shape does it take, and what
must it honor"; every deeper question routes to a named leaf under `runner/`, loaded on
demand. The pack is a design contract only: it fixes vocabulary and obligations for a runner
that is not built, so that when a trigger earns the build, the work starts from a resolved
contract rather than a cold charter.

This document makes no build commitment: no code, no repository, no schedule — no build begins
until a T4 build trigger fires. Every inherited obligation is cited from its already-shipped
owning contract, never restated here.

## Charter scope — the autonomous-drain side only

The boundary between plugins and runner IS the governed work-item queue, split
interactive-upstream from autonomous-downstream:

- **Interactive upstream (plugins own it).** Everything interactive — interview, design,
  architect, decompose, triage — produces autonomous-eligible items, and the trigger adapters
  live where their signals natively land ([trigger-dispatch](../trigger-dispatch.md)). The
  runner never decides what to build.
- **Autonomous downstream (the runner owns it).** The runner is the autonomous drain side
  only: lease-claim from the work-item queue, execute in isolation, run the verification
  gates, apply the per-class merge policy, and escalate back to humans. It is one executor
  behind the [invocation-adapter seam](../trigger-dispatch.md#executor-surface-classes) —
  swapping executors leaves the trigger adapters untouched.

## Build triggers

The runner's graduation to build is gated: either T4 build trigger fires it, and neither is
assumed to have fired. Restated verbatim in substance (the executor references rendered in the
shipped surface-class vocabulary, never as vendor names):

- The `C2` promotion trigger fires (per the [guardrail matrix](../guardrails.md#the-matrix))
  AND the existing executors behind the invocation-adapter seam — the self-operated and
  vendor-hosted surfaces reachable today — demonstrate a clean autonomous drain; **OR**
- those existing executors hit an isolation, concurrency, or platform wall the runner uniquely
  solves.

Until one build trigger is satisfied, the runner-execution home stays unborn and this pack
adds no runtime artifact. The trust loop earns the build; the build never front-runs the trust
loop (Boris step-3 trap: no agent-count scaling before the loop earns trust).

## Substrate stance — self-run primary, hosted via adapter

- **Self-operated is primary.** The self-operated CLI/SDK surface class is the only class
  where merge policy is ownable — every vendor-hosted issue-to-change agent keeps a deliberate
  human-merge-gate — so the `C2` auto-merge promotion is reachable only self-run.
- **Vendor-hosted is reachable, capped.** Vendor-hosted surfaces stay reachable through the
  [invocation-adapter seam](../trigger-dispatch.md#executor-surface-classes) (it covers
  local-CLI and cloud-API shapes) but inherit their human-merge-gate: the matrix merge-policy
  column caps at human-gated on any vendor-hosted executor. Vendor-managed isolation remains a
  legitimate `L3` instance — untrusted-provenance (`C5`) work is its natural fit.
- **Classes, never vendors.** The contract names surface classes — self-operated versus
  vendor-hosted — and never a product.

## Inherited constraints

All imported unchanged; each is enforced by its owning contract, cited never restated:

- Execution substrate is at least `L2`, fail-closed where unavailable
  ([isolation ladder](../guardrails/isolation-ladder.md)).
- Per-class gates, merge policy, cost tier, and escalation come from the
  [guardrail matrix](../guardrails.md#the-matrix).
- Queue and lease are reused from the work-item capability's race-safe lease and its
  autonomous/human-gated classes — no second claim mechanism
  ([dispatch](../trigger-dispatch.md#dispatch)).
- No queue bypass: every dispatch funnels through the one entrypoint, and the audit trail is
  the trust loop ([trigger-dispatch](../trigger-dispatch.md)).

## Anti-goals

- Set-and-forget framing — the runner is monitored by exception, never unattended-and-trusted.
- Ungated autonomy — every class keeps its matrix gates; no class drains without them.
- Privileged-context trigger footguns — the trigger class that runs fork-authored code with
  write-scoped credentials is never a runner intake path.

## Composition spine

The spine is specified in two layers: a normative layer that fixes its shape in seam
vocabulary, and a binding layer that records how the shape is realized at build time.

### Normative spine shape

The runner's shape is minimal composable orchestration over two pluggable seams crossed with
one execution split:

- a **pluggable sandbox-provider seam** — the isolation policy seam, selecting the substrate
  that satisfies a class's isolation floor;
- a **pluggable agent-adapter seam** — the invocation adapter seam, normalizing an executor's
  native surface behind one contract;
- an **autonomous/interactive split** — the runner drives the autonomous path; the interactive
  path stays with the plugins.

The [eight seams](runner/seams.md) are this spine's complete interface set — nothing in the
spine is expressible outside them.

### Binding stance — adopt first

The binding layer records an adopt-first posture: adopt the qualifying composition-spine
library as a build-stage dependency rather than build orchestration from scratch, absorbing
its orchestration, sandbox, and lifecycle patterns re-expressed in this pack's vocabulary. The
choice is re-verified at trigger time on maintenance, license, and seam fit; reimplementing the
pattern is the named fallback when re-verification fails. No library is named here — the
qualifying candidate is re-checked when the build trigger fires, not pinned in the design.

## Glance-layer rule

The charter, the spine shape, and the seam list above are the whole glance layer. Every deeper
question routes to a named leaf under `runner/`; depth is never answered from this document:

| Deeper question | Leaf |
|---|---|
| What each seam obligates, what owns it, and its runner-side interface tokens | [seams](runner/seams.md) |
| The full lifecycle state model and each transition's telemetry | [lifecycle](runner/lifecycle.md) |
| The stop-criteria taxonomy, terminal-handoff escalation, and severity routing | [escalation](runner/escalation.md) |
| Ownership seams, the launch backend set, and birth-time decisions | [topology](runner/topology.md) |

The `lifecycle`, `escalation`, and `topology` leaves land with the pack's later phase; their
forward links are expected within an in-progress design pack.
