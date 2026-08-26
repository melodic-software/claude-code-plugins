---
description: "Configure the autonomy plugin for this repository: discover the adopting org's state (role homes, substrate availability, budget posture), interview where discovery cannot infer, and write the schema-versioned binding under .claude/autonomy/. Use when: 'set up autonomy', 'autonomy setup', 'configure autonomy', 'bind the autonomy contracts', or another autonomy capability reports a missing binding. Re-runnable. Safe to invoke again to reconfigure."
argument-hint: "check | apply [--org-policy-home <locator>|none] [--budget-posture free|paid-opt-in]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Discovery phase of autonomy adoption (v0). Maps the roles in
[`${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md`](${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md) to this org's real instances
and records the result as the schema-versioned binding the resolution ladder in
[`${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md) reads at the repo-local layer. Never assumes
any org, repo, tracker, or fleet shape. Discovery reads what exists, the interview fills what
it cannot infer, and every landed change is reviewable per
[`${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md`](${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md).

## Actions

- **`check`** (read-only): resolve the effective binding across ALL rungs of the binding-seam
  resolution ladder. User-global (`~/.claude/autonomy/`) → project (`.claude/autonomy/`) →
  local overlay (`.claude/autonomy/**/*.local.*`), additive, PLUS the org rung when the merged
  layers carry an `org_policy_home` pointer: fetch the org binding via the host CLI with the
  consumer's own auth and fold it in at its ladder position. Report what is bound, what is
  missing, and which layer or rung contributes each value; an unreachable org-policy home is
  WARNED as not-considered, never silently omitted. No writes.
- **`apply`** (idempotent): run discovery, then write or update the project binding. Re-running
  reads the existing binding and proposes deltas; it never overwrites blind and never touches
  unrelated user content. All project paths anchor at the PROJECT ROOT. Resolve
  `${CLAUDE_PROJECT_DIR}` (fall back to the repository toplevel) before writing; invoking the
  skill from a subdirectory must never create a nested `.claude/autonomy/`.

## Argument surface (enumerated)

| Argument | Values | Headless default |
|---|---|---|
| action | `check` \| `apply` | (required) |
| `--org-policy-home` | repository locator, optionally `#<path>` to the binding document \| `none` | `none` |
| `--budget-posture` | `free` \| `paid-opt-in` | `free` |

A locator without `#<path>` triggers document discovery at bind time (the binding instance
document is found by its schema-versioned shape per the org repo's own layout) and the
resolved path is persisted alongside the pointer so later fetches are deterministic.

`apply` with every argument supplied runs non-interactively, no prompts, so automation and
headless use work. With arguments missing, discovery infers first and interviews only the
gaps (convention ladder: config present → use it; absent → infer and persist; cannot infer →
ask and offer to persist; otherwise → safe free-tier default).

## Discovery (apply)

1. **Role homes**: inspect the repository and, when a host CLI with the consumer's own auth is
   available, the org, which repositories hold the CI-orchestration, settings-as-code, and
   org-policy roles. A solo/no-org adopter terminates at the binding-seam contract's terminal
   default: the repo-local binding is the whole binding, free-tier defaults throughout.
2. **Substrate availability**: what execution surfaces exist (local machine, CI runners,
   self-run infrastructure). Recorded as declared posture, not probed destructively.
3. **Budget posture**: `free` unless the user explicitly opts into `paid-opt-in`; anything
   paid is advisory + explicit opt-in with cost surfaced first (wiring-vs-advisor).

## Written binding

`apply` writes `.claude/autonomy/binding.json` with these serialized keys:

- `schema_version` (string, from `"1.0"`);
- `roles`, an object keyed by the kebab-case role names of the role-topology contract
  (`capability-distribution-home`, `ci-orchestration-home`, `settings-as-code-home`,
  `org-policy-home`, `runner-execution-home`); a value MAY be null (unborn role, or no org
  instance, never invented);
- `org_policy_home`, the pointer (or `null`), with its resolved document path when
  discovered;
- `budget_posture`. `free` | `paid-opt-in`;
- `substrate`, an object with kebab-case surface keys (`local-machine`, `ci-runners`,
  `self-run-infrastructure`), boolean values.

The same file name is the shape at EVERY layer: the user-global layer is
`~/.claude/autonomy/binding.json`, the project layer `.claude/autonomy/binding.json`, and
each layer's personal overlay `binding.local.json` beside it. The project file is tracked
(team-shared); recommend the consumer `.gitignore` line: `.claude/autonomy/**/*.local.*`.
Layers resolve per the binding-seam ladder. User-global → org binding (when pointed) →
project → local overlay. Additively. Capability slices (like telemetry below) add their
sections ADDITIVELY under their slice name: a binding without a slice's section is valid
(absent-section tolerance) and no schema major bump is needed for an additive section.

## Telemetry slice

Wires the emitting state of
[`${CLAUDE_PLUGIN_ROOT}/reference/telemetry.md`](${CLAUDE_PLUGIN_ROOT}/reference/telemetry.md)
for all three execution contexts, discovery-first. Everything lands as reviewable changes;
paid sinks are advisory + explicit opt-in with cost surfaced first.

1. **Detect an existing observability stack**. Interview + repo/env inspection (`OTEL_*`
   endpoints in settings/env blocks, collector configs, known backend config files). Found →
   wire emission toward it: agent-session env block (settings `env`) and a CI emission snippet
   pointing at the org's endpoint. Paid/hosted stack → advisory with cost surfaced before any
   opt-in.
2. **No stack → the file-artifact free default** (zero paid dependencies):
   - CI pipeline spans via the OTLP JSON-lines writer snippet. Read
     [`templates/ci-otlp-artifact.md`](templates/ci-otlp-artifact.md) when `apply` reaches this
     step for the snippet, uploading the artifact directory per run;
   - agent-session signals via the ephemeral per-job collector in the same template (single
     static OSS collector binary + file-exporter config writing JSON-lines into the same
     artifact directory. Per-job, no standing infrastructure);
   - interactive sessions get the same coverage: env block toward the discovered stack when
     one exists, else a local collector instance (same binary + config template) exporting
     into a local query-on-read store directory.
   - Cost caveat surfaced on private repos: artifact storage and per-job collector runtime
     draw from metered pools.
3. **Agent-session wiring (Claude Code specifics)**. `CLAUDE_CODE_ENABLE_TELEMETRY=1`,
   per-signal `OTEL_*_EXPORTER` values, and for work-item-dispatched sessions
   `OTEL_RESOURCE_ATTRIBUTES` carrying `autonomy.work_item.url=<canonical item URL>` (the
   vendor attaches resource attributes to every metric datapoint and event. Verified against
   the official monitoring doc). Headless `-p` sessions inherit `TRACEPARENT`/`TRACESTATE`
   from the environment only under the enhanced-telemetry beta, the default surface starts
   a fresh root and joins query-side via the resource attribute (verified empirically). And
   interactive sessions deliberately ignore inbound trace context. Traces stay beta behind
   `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`; the slice treats spans as optional and never
   depends on beta span shapes.
4. **Record the binding**. Sink class, endpoint or artifact path, and the semconv pin land
   as the `telemetry` section of the schema-versioned binding.
5. **Conformance**. Run
   [`scripts/check-emission-conformance.mjs`](scripts/check-emission-conformance.mjs) against
   produced OTLP JSON-lines to verify the pinned `schemaUrl` and the join attribute before
   declaring the emitting state reached.

## Return-accounting capture slice

Wires the capture-enabled state of
[`${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md`](${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md),
discovery-first: detect the tracker class and close-flow surface, WIRE the close- and
reply-triggered attestation handlers via the close-triggered snippet in
[`templates/return-capture.md`](templates/return-capture.md) where machine-editable (the
marker-keyed comment floor, or provenance-verifiable native fields), ADVISE where GUI-only or
entitlement-gated, and record the
`capture` section of the repo-local autonomy binding. Read
[`context/capture-slice.md`](context/capture-slice.md) when `apply` reaches the capture slice: it
owns the autonomous-class capture gate, the record-integrity rule, the attestation-routing rule,
and every serialized `capture` key. Agents prompt and aggregate; they never estimate the two
human-attested return fields.

## Trigger/dispatch slice

Wires the signal-adapter and dispatch state of
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md),
discovery-first: discover the four signal-surface classes and their transports, wire the DIY floor
(event kick + scheduled drain) as reviewable changes through the one queue-drain entrypoint, advise
plan-gated integrations, and record the `triggers` section (the `surfaces` map + drain cadence) of
the repo-local autonomy binding. Vendor event names and invocation flags live in this slice's
[`templates/trigger-adapters.md`](templates/trigger-adapters.md) (adapter shapes) and
[`templates/ack-reply.md`](templates/ack-reply.md) (acknowledgment shape), never the contract.
Read [`context/trigger-dispatch-slice.md`](context/trigger-dispatch-slice.md) when `apply`
reaches the trigger/dispatch slice: it owns the per-surface adapter obligations, the
execution-surface attestation caveat, the admission fail-closed rule, every serialized `triggers`
key, and the [`scripts/check-signal-envelope.mjs`](scripts/check-signal-envelope.mjs) conformance
step.

## Guardrail binding resolution

How guardrail policy resolves across the TWO governance surfaces the guardrail contract
splits policy into. This section owns resolution; the [guardrail slice below](#guardrail-slice)
(detect → bind → live-validate → fail-closed) is the action that produces the security binding
this order resolves.

**Two-surface split.** Security-sensitive guardrail axes. Isolation bindings with their
runtime markers, merge policy, verification blocking knobs, per-class verification
topology, promotion state, escalation
routes, admission rules and caps. Bind ONLY in the security binding document in the
settings-as-code home, outside the blast radius of the agents it governs. Its schema is
contract-owned and ships at
[`schemas/guardrails-security-binding.schema.json`](schemas/guardrails-security-binding.schema.json);
[`scripts/check-security-binding.mjs`](scripts/check-security-binding.mjs) validates a
document (schema shape + the semantic rules the schema cannot express) and, with
`--evidence`, resolves each promotion cell's EFFECTIVE state against a promotion-evidence
source, the bound state is a ceiling contrary evidence lowers without writing the
binding. Read the
[admission-policy leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/admission-policy.md) directly
when binding admission rules and caps: it owns the decision table, the wildcard precedence rule,
and the `override_justification` floor those caps enforce. Non-security axes remap in the
additive `guardrails` section of the repo-local binding: class→label strings (which local label
means which work class; read the
[work-classes leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/work-classes.md) directly when
resolving what a label maps to; it owns the risk-property bundles and promotion discipline behind
each class) and cost-tier→model names. Vocabulary remaps only, never policy content.

**A third home that is not a governance surface.** Two axes of the
[verification-topology leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/verification-topology.md)
bind in this plugin's `userConfig` rather than either governance surface: the verification lens
pool, and whether the advisory visual narration lane runs. Neither counts anything, the pool
contributes to no floor, and the narration lane has no security-binding cell at all, so neither can
weaken a floor, which is what lets them sit on an operator surface. Plugin options resolve from
user, `--settings`, and managed settings only; a watched repository's own `.claude/settings.json` is
not read for them, so a repo cannot dial its own verification. The slice proposes neither as a
binding field.

**Layered resolution order.** Org-policy-home defaults → settings-as-code per-repo
security binding → repo-local non-security remaps. Later layers refine earlier ones for
NON-SECURITY axes only; no repo-local (agent-writable) value ever supplies or overrides a
security axis.

**Security-binding locator registry.** When settings-as-code is a separate repository,
the org-policy home carries the repo→security-binding-document registry the dispatch seam
resolves each repository's security binding through. One registry, resolvable per repo,
on the org governance surface.

**Agent-unwritable bootstrap for security resolution.** The repo-local `org_policy_home`
pointer is tolerable for non-security defaults only, a repo-writable pointer would let
an agent redirect the whole chain to a forged policy repository carrying a forged
registry, binding, and matching runtime markers. For SECURITY resolution the seam pins
the org-policy-home identity from an agent-unwritable bootstrap: org-level platform
configuration outside repo blast radius (an org-level setting or variable repo agents
cannot write) or the executor's trusted deployment config. Any security resolution that
would depend on a repo-writable pointer, or an unresolvable locator, fail-closes
autonomous dispatch, naming the compliant path (pin the home in org-level configuration
or the executor's deployment config).

**Fail-closed.** An absent or invalid security binding blocks autonomous dispatch.
Every signal enqueues human-gated. Documented defaults exist only for non-security axes;
no security axis ever resolves from a documented default or a repo-local surface.

## Guardrail slice

Wires the enforced state of the [guardrail contract](${CLAUDE_PLUGIN_ROOT}/reference/guardrails.md)
(open it, then the `guardrails/<leaf>.md` it routes to, for whatever axis is in question): detect,
bind, live-validate, fail-closed, always detect-diff-reconciling against the org's EXISTING
guardrail surfaces. The [resolution section above](#guardrail-binding-resolution) owns how bound
policy resolves; this slice is the action that produces the security binding it resolves. Read
[`context/guardrail-slice.md`](context/guardrail-slice.md) when `apply` reaches the guardrail
slice: it owns the per-layer wiring, the isolation-ladder probe (recipe in
[`templates/isolation-probe.md`](templates/isolation-probe.md)), the security-binding schema and
its validator, and the paid-SKU opt-in surface. The slice is argument-selected, so a run that does
not select it never needs the file.

## Routine slice

Wires the standing-routine state of the
[routine catalog](${CLAUDE_PLUGIN_ROOT}/reference/routines.md) (read it to pick a routine; each
recipe is a leaf under `routines/`): a routine is a scheduled
`temporal`-class signal adapter behind the governed queue, never a private execution or merge path.
Like the [guardrail slice](#guardrail-slice) it PREPARES the security surface and never writes it.
Read [`context/routine-slice.md`](context/routine-slice.md) when `apply` reaches the routine slice:
it owns the discovery-first reconciliation against the org's existing schedulers and bots, the
[`templates/routine-definitions.md`](templates/routine-definitions.md) template, the CI-cron
handler shape, and the signal-envelope verification. The slice is argument-selected, so a run
that does not select it never needs the file.

## Prerequisite-resolution slice

Extends this skill per its own extension model for
[routine prerequisite resolution](${CLAUDE_PLUGIN_ROOT}/reference/prerequisite-resolution.md).
Read
[`context/prerequisite-resolution-slice.md`](context/prerequisite-resolution-slice.md) when
`apply` reaches the prerequisite-resolution slice: it owns the binding-section JSON shape and
the wrapper scripts' non-interactive flags.

**Liveness.** The slice `check` is an engine health-check surface: it invokes
[`scripts/resolve-prerequisites.mjs`](scripts/resolve-prerequisites.mjs) end-to-end and
fails loud on internal failure, never a verdict-shaped fallback.

1. **`check`**. For each scheduling surface already recorded under `triggers` / `routines`
   (this slice declares no `surfaces` map of its own), report per-identity verdicts with
   provenance via
   [`scripts/check-prerequisite-resolution.mjs`](scripts/check-prerequisite-resolution.mjs).
   A bare repo yields `unsupported` / `unknown` for every identity, never an error.
2. **`apply`**. Detect-diff-reconcile against existing `prerequisite_resolution`
   declarations; a declaration contradicting a ran-negative probe is a finding (identity
   stays negative while the finding is open. ADR 0011 Decision 2). The prose-context pass
   reads `CLAUDE.md` / `AGENTS.md` (session-reachable only by reference) / `README` to
   *propose* declarations into **non-security keys only**; the human ratifies; the slice
   writes the additive section (`surface_refs` + `declarations`, no `surfaces` map).
   Narrowing-only enablement: enable in `routines.enabled` only when the verdict clears;
   negative/`unknown` routes to the advisory path. Org-rung entitlements are interviewed,
   never auto-written. Non-interactive contexts skip ask-and-persist and report assumptions.
   Security-binding changes are **prepared**, never written.
   Wrapper:
   [`scripts/apply-prerequisite-resolution.mjs`](scripts/apply-prerequisite-resolution.mjs).

## Runner note

The [runner design pack](${CLAUDE_PLUGIN_ROOT}/reference/runner.md) is bindable-when-born:
until a build trigger fires and the runner-execution home is born, setup records NOTHING
runner-specific. No probe, no wiring, no binding section for the unborn home. The single
exception is escalation notification routes, which already home on the security surface: the
severity axis (`notice`/`attention`/`urgent`) and the personal-push tier are prepared as route
options through the security binding's `escalation_severity`, `escalation_severity_routes`, and
`escalation_ack` keys, a reviewable change on the settings-as-code home like every other
security axis, never repo-local. The route set, its two-step severity resolution, and the
per-class default severities are specified by the
[runner escalation leaf](${CLAUDE_PLUGIN_ROOT}/reference/runner/escalation.md); this note points
there rather than restating them. The full lifecycle state model and each transition's telemetry
are specified by the
[runner lifecycle leaf](${CLAUDE_PLUGIN_ROOT}/reference/runner/lifecycle.md); read it directly
when tracing how a leased item moves through its states, since this note does not restate the
state machine. The ownership-seam map assigning each part of the runner to its owning home is
specified by the [runner topology leaf](${CLAUDE_PLUGIN_ROOT}/reference/runner/topology.md); read
it directly when placing a runner obligation on its home, since this note does not re-derive the
split.

## Gotchas

Editing- and run-time failure modes, the two-binding split (repo-local autonomy binding vs the
separate security binding), the spell gate splitting coined hyphenated compounds, and a scheduling
surface recorded in two `surfaces` maps resolving as ambiguous, are catalogued in
[`context/gotchas.md`](context/gotchas.md).

## What this skill does NOT do

- Wire capability slices that have not shipped yet. Each lands with its own work package and
  extends this skill (the runner charter execution pack remains the next such slice after
  prerequisite-resolution).
- Estimate, impute, or backfill the two human-attested return fields. Ever.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform setup
  contract (`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" in the marketplace
  repository). Nor platform settings.
- Assume the shape of any particular org or fleet, a run against an unknown repo asks or
  defaults; it never guesses silently.
- Recommend or privilege any observability vendor. Sink classes only; the deployment picks
  instances.
