# Routine wiring shapes

Per-scheduling-surface-class shapes the [routine slice](../SKILL.md) wires for a standing
routine. `<...>` placeholders resolve from the detected surface and the routine's catalog class at
wire time; no org, fleet, or vendor value is baked in — scheduler and platform names appear only
as marked examples. Every shape is a `temporal`-class signal adapter: its handler emits ONE signal
into the governed work-item queue and the standing drain dispatches it through the one entrypoint.
A routine NEVER executes work in its own handler and never opens a second scheduling, execution, or
merge path — the handler's only job is to enqueue the `temporal` signal per the
[trigger-dispatch contract](../../../reference/trigger-dispatch.md).

## The enqueue contract (all surface classes)

Constant across every shape — the routine handler does exactly this and no more:

| Step | What the handler does |
|---|---|
| Emit | writes ONE `temporal` signal envelope onto a governed queue item (the `<!-- autonomy:signal:v1 -->` marker record); it never runs the routine's own work |
| Stamp identity | sets `signal.routine` to the routine's IDENTITY — `<class-token>`, or `<class-token>/<posture-token>` for a multi-posture class — a CLAIM the handler makes, never a trust anchor |
| Stamp source | sets `signal.source_surface` to the routine's recorded scheduling-surface id so the envelope check resolves it against the binding's `routines` (or `triggers`) `surfaces` map |
| Stamp producer | sets `signal.producer_identity` from the platform's authenticated run context — the workflow-file or scheduler-unit reference the platform injects — never from job arguments; admission checks it for equality with the entry's ratified `producer_identity` |
| Carry class | leaves `signal.work_class` to admission, which stamps it only after validating the `(signal.routine, attested source surface)` pair against the security binding's `admission.classification.temporal` table AND that `signal.raw_link` falls under that entry's ratified `run_link_prefix` AND that the attested `signal.producer_identity` equals the entry's ratified `producer_identity`; the handler never self-stamps a class |
| Raw link | `signal.raw_link` = the surface's durable reference (an https run permalink on a `ci-cron` surface, a durable `file:`/artifact URI on a `local-scheduler` surface) — itself a CLAIM, admitted only when it falls under the surface's ratified `run_link_prefix` |
| Trace | injects `signal.traceparent` so the causal tree spans schedule → queue → agent session |
| No dispatch | returns after enqueue; the standing drain claims and dispatches through the one entrypoint |

`scheduler_class` is a closed two-value discriminator (`ci-cron` \| `local-scheduler`); the surface
classes below each RECORD as one of the two by the raw-link form, never as a new token.

The `--routine` argument, the workflow file, and the emitted `--raw-link` are all CLAIMS, not
trust anchors: the security binding's protected identity↔surface association is authoritative. Each
of its entries carries `{class, source_surface, run_link_prefix, producer_identity}` and binds
exactly ONE routine identity per emitting surface. The `run_link_prefix` — the run permalink
namespace, which may be repo-scoped and SHARED across a repo's schedules rather than disjoint per
entry — is recorded at binding review, NOT emitted by the job; the `producer_identity` (the
platform-attested workflow-file or scheduler-unit reference) is the per-schedule pin WITHIN that
namespace and is unique across entries. A shape below therefore emits for a SINGLE identity (a
multi-posture class runs one shape per posture on its own surface), so the platform-attested
producer pins the identity, and a swapped `--routine`, or a forged `--raw-link` — whether outside
the ratified prefix or under it but from another schedule — cannot resolve a different class,
because the attested `producer_identity` must equal the ratified value.

## CI-cron surface (marked example: a hosted CI scheduler)

`scheduler_class: ci-cron`, `raw_link` an https run permalink. The scheduled handler lands on the
CI-orchestration home; the enabling settings on the settings-as-code home.

```yaml
# <ci-orchestration-home>: scheduled job for ONE routine identity — emits the signal, runs no work.
# The identity is a claim; the security binding's identity->surface table is the trust anchor.
on:
  schedule:
    - cron: "<cadence-for-identity>"    # org-bound cadence for <routine-identity>
  workflow_dispatch: {}                # manual kick
jobs:
  emit-routine:
    steps:
      - run: <enqueue-command> \
          --surface "<ci-cron-surface-id>" \
          --class temporal \
          --routine "<routine-identity>" \
          --raw-link "<https-run-permalink>"
```

## Local-scheduler surface (marked example: a developer-machine or self-run OS scheduler)

`scheduler_class: local-scheduler`, `raw_link` a durable `file:`/artifact URI (declare
`artifact_schemes` on the surface entry when an org artifact store holds the run record).

```sh
# <local scheduler>: periodic job for ONE routine identity — enqueue only, no routine work
<enqueue-command> \
  --surface "<local-scheduler-surface-id>" \
  --class temporal \
  --routine "<routine-identity>" \
  --raw-link "file://<durable-run-record-path>"
```

## Self-run infrastructure (marked example: a self-operated scheduler on org-run hardware)

The raw-link form is the discriminator, not a separate token: records as `ci-cron` when the
surface issues an https run permalink, else `local-scheduler` with a durable local/artifact
`raw_link`. The handler is the same enqueue-only shape as the two above.

## Vendor-hosted preview surface (marked example: a preview-stage hosted scheduler) — advisory

A vendor-hosted or preview scheduler that carries a plan/seat cost is NOT wired by default:
surface the cost, take explicit opt-in, then wire it as `ci-cron` (https permalink) or
`local-scheduler` per its raw-link form. Preview surfaces are moving targets — re-verify against
current vendor docs at wire time, never from this template.

## Parameterization

One shape per (routine identity × cadence × surface), and — because the security binding permits
one identity per surface — one identity per emitting surface. The identity selects the catalog
definition (posture leaf for a multi-posture class) and the `admission.classification.temporal`
entry the signal's work class is stamped from; that entry's `run_link_prefix` and its
`producer_identity` are ratified at binding review — the prefix pinning the (possibly shared)
run-permalink namespace, the producer identity pinning this schedule within it. Cadence and
surface choice come from the repo-local `routines` section.
A reconciled existing bot reuses this table by recording its identity and its surface — wiring
nothing new — so the same concern never carries two mechanisms.
