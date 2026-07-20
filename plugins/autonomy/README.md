# autonomy

Governed autonomous agent operation. This plugin is the capability-distribution home for the
AI-adoption-ladder contract set: it ships the tool-agnostic contracts an adopting org binds to
its own repositories, tools, and policies, plus a guided-setup skill that discovers the org's
state and records that binding.

## Shipped capability (0.7.0)

- **Topology contracts** (`reference/`): role topology for the repositories an adoption spans,
  the binding-seam shape that maps contract roles to an org's real instances, and the
  wiring-vs-advisor principle governing how setup lands changes.
- **Telemetry contract** (`reference/telemetry.md`): standards-pinned OTLP from every execution
  context, the `autonomy.work_item.url` join attribute, one causal tree by context propagation,
  sink classes with a zero-cost file-artifact default — plus the setup telemetry slice, its
  snippet templates, and the emission-conformance check.
- **Return-accounting convention** (`reference/return-accounting.md`): the two human-attested
  return questions captured as a tracker-resident record at the task boundary of
  autonomous-class work, joinable to cost telemetry by the join attribute — plus the setup
  capture slice and its close-boundary templates. Agents prompt and aggregate; they never
  estimate the human fields.
- **Trigger-dispatch contract** (`reference/trigger-dispatch.md`): four signal-surface
  classes normalized by adapters into the governed work-item queue under six class-generic
  obligations, a schema-versioned signal envelope, security-surface work-class stamping, and
  one dispatch entrypoint (push kick + scheduled drain through the queue seam's race-safe
  lease) — plus the setup trigger/dispatch slice, its adapter and acknowledgment templates,
  and the signal-envelope conformance check.
- **Guardrail matrix** (`reference/guardrails.md`): five semantic work classes (`C1`–`C5`)
  crossed with five enforcement columns — isolation floor, verification layers, merge policy,
  cost tier, escalation — as one progressive-disclosure hub with on-demand leaves (isolation
  ladder, work classes, security review, admission policy), human-ratified promotion with
  automatic fail-closed demotion, and a two-surface binding split by governance sensitivity
  (security axes on the settings-as-code home outside agent blast radius; non-security remaps
  repo-local) — plus the contract-owned security-binding schema and its semantic check, and the
  setup guardrail slice that detects substrates per surface, live-validates isolation with an
  in-boundary probe before binding, folds in security-review wiring, and fail-closes autonomous
  dispatch where no `L2` substrate exists.
- **Standing-routine catalog** (`reference/routines.md`): the routine classes an adopting org can
  stand up as governed background maintenance — a progressive-disclosure hub whose glance-layer
  table classifies every class (judgment, output, access → derived guardrail row) under
  contract-owned catalog-to-matrix mapping rules, with `reference/routines/` definition leaves for
  the v1 subset and the invariant that a routine is a scheduled `temporal`-class trigger adapter
  behind the governed queue, never a private execution or merge path — plus the setup routine slice
  that discovers scheduling surfaces, wires the free CI-cron/local-scheduler defaults as reviewable
  changes, homes each routine's work-class mapping on the security surface, and
  detect-diff-reconciles existing org schedulers and bots instead of duplicating them.
- **Runner design pack** (`reference/runner.md`): the architect-ready design contract for the
  autonomous-drain runner — the composition spine and its eight seams, the lifecycle state
  model, the two-family stop-criteria taxonomy with terminal-handoff escalation and
  severity-routed notification fan-out, the matrix-derived launch backend set, and the topology
  ownership seam map, as a progressive-disclosure hub with `reference/runner/` leaves. Design
  only — the build stays gated on the charter's own triggers and the runner-execution home
  stays unborn; setup records nothing runner-specific beyond the escalation notification routes
  (severity axis + personal-push tier) bound through the security binding.
- **Guided setup** (`/autonomy:setup`): discovery-first interview of the adopting org's state —
  role homes, substrate availability, budget posture — writing a schema-versioned binding under
  `.claude/autonomy/` as reviewable changes. Never assumes any particular org or repo shape.

## Roadmap (deferred, trigger-gated)

Each capability below lands with its own work package; none ships before its contracts are
locked (no step-skipping — trust before scale).

| Capability | Trigger |
|---|---|
| Fleet adapter materializations (reusable workflows, labels, drain routine) | Work-item backlog, post trigger-package graduation. |
| Runner charter execution pack (design pack shipped) | The runner build trigger fires (charter's own conditions). |

## Trigger register (plugin-scoped)

| Trigger | Action |
|---|---|
| Role vocabulary changes in `reference/role-topology.md` | Update the org-policy home's binding instance doc to the new vocabulary version. |
| A second plugin consumes `.claude/autonomy/` config | Graduate the binding schema to a versioned concern contract per the marketplace's concern-named-folder convention. |

## Configuration

Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named — the
config outlives any plugin restructure). Personal overlays follow the marketplace overlay
convention: `.claude/autonomy/**/*.local.*` stays gitignored; layers resolve per the
binding-seam ladder — user-global → org binding (when pointed) → project → local overlay —
additively.
