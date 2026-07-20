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
| Stamp source | sets `signal.source_surface` to the routine's recorded scheduling-surface id so the envelope check resolves it against the binding's `routines` (or `triggers`) `surfaces` map |
| Carry class | leaves `signal.work_class` to the admission classification the security binding homes for the routine's class token — the handler never self-stamps a class |
| Raw link | `signal.raw_link` = the surface's durable reference: an https run permalink on a `ci-cron` surface, a durable `file:`/artifact URI on a `local-scheduler` surface |
| Trace | injects `signal.traceparent` so the causal tree spans schedule → queue → agent session |
| No dispatch | returns after enqueue; the standing drain claims and dispatches through the one entrypoint |

`scheduler_class` is a closed two-value discriminator (`ci-cron` \| `local-scheduler`); the surface
classes below each RECORD as one of the two by the raw-link form, never as a new token.

## CI-cron surface (marked example: a hosted CI scheduler)

`scheduler_class: ci-cron`, `raw_link` an https run permalink. The scheduled handler lands on the
CI-orchestration home; the enabling settings on the settings-as-code home.

```yaml
# <ci-orchestration-home>: scheduled job — emits the routine signal, runs no routine work
on:
  schedule:
    - cron: "<cadence-for-class>"      # org-bound cadence for <routine-class-token>
  workflow_dispatch: {}                # manual kick
jobs:
  emit-<routine-class-token>:
    steps:
      - run: <enqueue-command> \
          --surface "<ci-cron-surface-id>" \
          --class temporal \
          --routine "<routine-class-token>" \
          --raw-link "<https-run-permalink>"
```

## Local-scheduler surface (marked example: a developer-machine or self-run OS scheduler)

`scheduler_class: local-scheduler`, `raw_link` a durable `file:`/artifact URI (declare
`artifact_schemes` on the surface entry when an org artifact store holds the run record).

```sh
# <local scheduler>: periodic job — enqueue only, no routine work in the handler
<enqueue-command> \
  --surface "<local-scheduler-surface-id>" \
  --class temporal \
  --routine "<routine-class-token>" \
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

One shape per (routine class token × cadence × surface). The class token selects the catalog
definition and the `admission.classification.temporal` entry the signal's work class is stamped
from; cadence and surface choice come from the repo-local `routines` section. A reconciled existing
bot reuses this table by recording its surface and class token — wiring nothing new — so the same
concern never carries two mechanisms.
