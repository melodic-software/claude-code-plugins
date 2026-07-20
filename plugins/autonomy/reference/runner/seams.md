# Runner seams

The eight seams are the runner's complete interface set — the spine shape in
[the hub](../runner.md) is expressible only through them. Each seam below states its
obligations in contract vocabulary, cites the already-shipped contract that owns any inherited
portion (linked, never restated — the pack defines only runner-new content), and names the
runner-side interface tokens that are resolved at this phase. The structured-output envelope's
field names resolve here; every other exact seam token, and all lifecycle, terminal-outcome,
and severity tokens, resolve at `/architect` and in the pack's escalation and lifecycle leaves.

Three seams carry an already-shipped owning contract — queue+lease, isolation policy, and
observability+cost; the other five are runner-new, though several plug into a shipped boundary
they cite rather than redefine.

## Invocation adapter

The runner is one executor behind one adapter contract that normalizes every executor surface
— self-operated CLI/SDK and vendor-hosted cloud-API shapes alike — into a uniform invoke
operation. Swapping the executor leaves the upstream trigger adapters untouched; the
executor-class determination that gates merge policy is security-surface data, never a
repo-local value.

- **Plugs into (shipped):** the [executor surface classes](../trigger-dispatch.md#executor-surface-classes)
  and the [one-entrypoint invariant](../trigger-dispatch.md#dispatch) — the runner is the
  executor those cite, not a second dispatch path.
- **Interface tokens:** binds the shipped `executor_class` (`self-operated` | `vendor-hosted`);
  the runner-new adapter tokens resolve at `/architect`.

## Structured-output envelope

Every executor run hands back exactly one machine-readable envelope at its task boundary. The
envelope is the runner's single structured return — the carrier the verification, escalation,
and lifecycle seams consume; there is no second hand-back path. It records why the run stopped,
what terminal outcome that resolves to, a reference to the run's evidence bundle, and the
handle a human takeover resumes from.

- **Owning contract:** runner-new (no shipped contract owns it).
- **Interface tokens (resolved here):** `stop_reason`, `outcome`, `evidence` (an
  evidence-bundle reference, not the bundle inline), `resume_handle`. The value set for
  `outcome` and the stop-reason families are the [escalation leaf](escalation.md)'s subject;
  the lifecycle state tokens are the [lifecycle leaf](lifecycle.md)'s — referenced here, never
  defined.

## Queue and lease

The runner claims work through the work-item capability's race-safe lease and its single
dispatch entrypoint. There is no second claim, dispatch, or escalation mechanism anywhere; the
lease is the guarantor that one leased item maps to one emitting session, and the lease record
is protected dispatch data the runner reads, never rewrites.

- **Owning contract:** [dispatch](../trigger-dispatch.md#dispatch) and the
  [adapter obligations](../trigger-dispatch.md#adapter-obligations) — cited, never restated.
- **Interface tokens:** binds the shipped per-run knobs `autonomous_concurrency` and
  `items_per_run`, owned by the admission policy on the security surface.

## Isolation policy

The runner runs each work class at or above its isolation floor and fail-closes where the
floor is unavailable — the sandbox-provider seam selects a substrate that satisfies the floor,
and an unattestable or unbound substrate blocks dispatch rather than degrading it.

- **Owning contract:** the [guardrail matrix](../guardrails.md#the-matrix) min-isolation column
  and the [isolation ladder](../guardrails/isolation-ladder.md) leaf.
- **Interface tokens:** binds the shipped ladder levels `L0`–`L3` and the security binding's
  isolation entries; the runner-new provider-selection tokens resolve at `/architect`.

## Outcome-verification gate

Before disposition, the runner runs the class's verification layers and resolves a pass/fail
result. A failed blocking gate is a terminal stop surfaced through the envelope, never a silent
pass or a merge the policy would gate.

- **Plugs into (shipped):** the [verification column](../guardrails.md#the-matrix) and the
  [security-review leaf](../guardrails/security-review.md) own which layers exist and which
  block per class; the gate-running mechanism is runner-new.
- **Interface tokens:** the gate writes its result into the envelope's `stop_reason` and
  `outcome`; the exact gate tokens resolve at `/architect`.

## Merge-policy toggle

The runner applies the per-class merge policy and never lands a change the policy gates. The
toggle honors the matrix merge-policy column and the vendor-hosted human-merge-gate cap: on any
vendor-hosted executor, every class caps at human-gated regardless of its self-run row.

- **Plugs into (shipped):** the [merge-policy column](../guardrails.md#the-matrix) and the
  vendor-hosted cap on the [executor surface classes](../trigger-dispatch.md#executor-surface-classes).
- **Interface tokens:** reads the shipped `executor_class` cap; the thin launch disposition and
  any growth-stage merge serialization are the [lifecycle leaf](lifecycle.md)'s subject.

## Observability and cost

Every lifecycle transition emits standard telemetry carrying the work-item join attribute and
the propagated trace context, so runner activity joins the one causal tree. At the task
boundary the runner also drives the return-accounting capture, which joins to machine cost by
the same attribute at query time. The runner adds no parallel telemetry schema and duplicates
no cost value.

- **Owning contracts:** [telemetry](../telemetry.md) owns emission, the join attribute, and the
  causal tree; [return-accounting](../return-accounting.md) owns the task-boundary capture and
  its query-side join.
- **Interface tokens:** binds the shipped `autonomy.work_item.url` join attribute and the
  return record's task-boundary fields; escalation telemetry rides the telemetry contract's
  custom-namespace mechanism, its exact namespace token read from that contract at build.

## Session, resume, and caps

The runner persists each executor session so a human takeover resumes it rather than restarting
from cold, and it enforces the caps that bound a single drain. The persisted session behind the
`resume_handle` is what turns a terminal escalation into a resumable takeover.

- **Plugs into (shipped):** the drain-level caps bind the admission-policy knobs
  ([admission policy](../guardrails/admission-policy.md), surfaced as `autonomous_concurrency`
  and `items_per_run` on the dispatch contract); session persistence is runner-new.
- **Per-item caps — owning home pinned.** The turn, budget, and wall-clock caps that bound a
  single run, and the retry budget behind the execution-error stop, are admission-policy knobs
  on the SECURITY binding — siblings of the drain-level pair, on the same agent-unwritable
  surface, for the same reason: a cap the governed agents could edit is no cap. Their exact
  keys land as ADDITIVE schema keys with the build (token names resolve at `/architect` like
  every other deferred seam token); the runner READS them and fail-closes at launch when they
  are unbound, so the `cap-exceeded` stop is deterministic and no item ever runs unbounded on
  implicit defaults.
- **Interface tokens:** the envelope's `resume_handle` is the takeover key; the caps whose
  exhaustion is a terminal stop are the [escalation leaf](escalation.md)'s
  stop-criteria subject.
