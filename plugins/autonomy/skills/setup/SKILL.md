---
name: setup
description: "Configure the autonomy plugin for this repository: discover the adopting org's state (role homes, substrate availability, budget posture), interview where discovery cannot infer, and write the schema-versioned binding under .claude/autonomy/. Use when: 'set up autonomy', 'autonomy setup', 'configure autonomy', 'bind the autonomy contracts', or another autonomy capability reports a missing binding. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply [--org-policy-home <locator>|none] [--budget-posture free|paid-opt-in]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Discovery phase of autonomy adoption (v0). Maps the roles in
[`${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md`](${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md) to this org's real instances
and records the result as the schema-versioned binding the resolution ladder in
[`${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md) reads at the repo-local layer. Never assumes
any org, repo, tracker, or fleet shape — discovery reads what exists, the interview fills what
it cannot infer, and every landed change is reviewable per
[`${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md`](${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md).

## Actions

- **`check`** (read-only): resolve the effective binding across ALL rungs of the binding-seam
  resolution ladder — user-global (`~/.claude/autonomy/`) → project (`.claude/autonomy/`) →
  local overlay (`.claude/autonomy/**/*.local.*`), additive, PLUS the org rung when the merged
  layers carry an `org_policy_home` pointer: fetch the org binding via the host CLI with the
  consumer's own auth and fold it in at its ladder position. Report what is bound, what is
  missing, and which layer or rung contributes each value; an unreachable org-policy home is
  WARNED as not-considered, never silently omitted. No writes.
- **`apply`** (idempotent): run discovery, then write or update the project binding. Re-running
  reads the existing binding and proposes deltas; it never overwrites blind and never touches
  unrelated user content. All project paths anchor at the PROJECT ROOT — resolve
  `${CLAUDE_PROJECT_DIR}` (fall back to the repository toplevel) before writing; invoking the
  skill from a subdirectory must never create a nested `.claude/autonomy/`.

## Argument surface (enumerated)

| Argument | Values | Headless default |
|---|---|---|
| action | `check` \| `apply` | — (required) |
| `--org-policy-home` | repository locator, optionally `#<path>` to the binding document \| `none` | `none` |
| `--budget-posture` | `free` \| `paid-opt-in` | `free` |

A locator without `#<path>` triggers document discovery at bind time (the binding instance
document is found by its schema-versioned shape per the org repo's own layout) and the
resolved path is persisted alongside the pointer so later fetches are deterministic.

`apply` with every argument supplied runs non-interactively — no prompts — so automation and
headless use work. With arguments missing, discovery infers first and interviews only the
gaps (convention ladder: config present → use it; absent → infer and persist; cannot infer →
ask and offer to persist; otherwise → safe free-tier default).

## Discovery (apply)

1. **Role homes**: inspect the repository and, when a host CLI with the consumer's own auth is
   available, the org — which repositories hold the CI-orchestration, settings-as-code, and
   org-policy roles. A solo/no-org adopter terminates at the binding-seam contract's terminal
   default: the repo-local binding is the whole binding, free-tier defaults throughout.
2. **Substrate availability**: what execution surfaces exist (local machine, CI runners,
   self-run infrastructure) — recorded as declared posture, not probed destructively.
3. **Budget posture**: `free` unless the user explicitly opts into `paid-opt-in`; anything
   paid is advisory + explicit opt-in with cost surfaced first (wiring-vs-advisor).

## Written binding

`apply` writes `.claude/autonomy/binding.json` with these serialized keys:

- `schema_version` (string, from `"1.0"`);
- `roles` — an object keyed by the kebab-case role names of the role-topology contract
  (`capability-distribution-home`, `ci-orchestration-home`, `settings-as-code-home`,
  `org-policy-home`, `runner-execution-home`); a value MAY be null (unborn role, or no org
  instance — never invented);
- `org_policy_home` — the pointer (or `null`), with its resolved document path when
  discovered;
- `budget_posture` — `free` | `paid-opt-in`;
- `substrate` — an object with kebab-case surface keys (`local-machine`, `ci-runners`,
  `self-run-infrastructure`), boolean values.

The same file name is the shape at EVERY layer: the user-global layer is
`~/.claude/autonomy/binding.json`, the project layer `.claude/autonomy/binding.json`, and
each layer's personal overlay `binding.local.json` beside it. The project file is tracked
(team-shared); recommend the consumer `.gitignore` line: `.claude/autonomy/**/*.local.*`.
Layers resolve per the binding-seam ladder — user-global → org binding (when pointed) →
project → local overlay — additively. Capability slices (like telemetry below) add their
sections ADDITIVELY under their slice name: a binding without a slice's section is valid
(absent-section tolerance) and no schema major bump is needed for an additive section.

## Telemetry slice

Wires the emitting state of
[`${CLAUDE_PLUGIN_ROOT}/reference/telemetry.md`](${CLAUDE_PLUGIN_ROOT}/reference/telemetry.md)
for all three execution contexts, discovery-first. Everything lands as reviewable changes;
paid sinks are advisory + explicit opt-in with cost surfaced first.

1. **Detect an existing observability stack** — interview + repo/env inspection (`OTEL_*`
   endpoints in settings/env blocks, collector configs, known backend config files). Found →
   wire emission toward it: agent-session env block (settings `env`) and a CI emission snippet
   pointing at the org's endpoint. Paid/hosted stack → advisory with cost surfaced before any
   opt-in.
2. **No stack → the file-artifact free default** (zero paid dependencies):
   - CI pipeline spans via the OTLP JSON-lines writer snippet in
     [`templates/ci-otlp-artifact.md`](templates/ci-otlp-artifact.md), uploading the artifact
     directory per run;
   - agent-session signals via the ephemeral per-job collector in the same template (single
     static OSS collector binary + file-exporter config writing JSON-lines into the same
     artifact directory — per-job, no standing infrastructure);
   - interactive sessions get the same coverage: env block toward the discovered stack when
     one exists, else a local collector instance (same binary + config template) exporting
     into a local query-on-read store directory.
   - Cost caveat surfaced on private repos: artifact storage and per-job collector runtime
     draw from metered pools.
3. **Agent-session wiring (Claude Code specifics)** — `CLAUDE_CODE_ENABLE_TELEMETRY=1`,
   per-signal `OTEL_*_EXPORTER` values, and for work-item-dispatched sessions
   `OTEL_RESOURCE_ATTRIBUTES` carrying `autonomy.work_item.url=<canonical item URL>` (the
   vendor attaches resource attributes to every metric datapoint and event — verified against
   the official monitoring doc). Headless `-p` sessions inherit `TRACEPARENT`/`TRACESTATE`
   from the environment only under the enhanced-telemetry beta — the default surface starts
   a fresh root and joins query-side via the resource attribute (verified empirically) — and
   interactive sessions deliberately ignore inbound trace context. Traces stay beta behind
   `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`; the slice treats spans as optional and never
   depends on beta span shapes.
4. **Record the binding** — sink class, endpoint or artifact path, and the semconv pin land
   as the `telemetry` section of the schema-versioned binding.
5. **Conformance** — run
   [`scripts/check-emission-conformance.mjs`](scripts/check-emission-conformance.mjs) against
   produced OTLP JSON-lines to verify the pinned `schemaUrl` and the join attribute before
   declaring the emitting state reached.

## Return-accounting capture slice

Wires the capture-enabled state of
[`${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md`](${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md),
discovery-first: detect the tracker class and close-flow surface, WIRE the close- and
reply-triggered attestation handlers where machine-editable (the marker-keyed comment floor, or
provenance-verifiable native fields), ADVISE where GUI-only or entitlement-gated, and record the
`capture` section of the repo-local autonomy binding. The autonomous-class capture gate, the
record-integrity rule, the attestation-routing rule, and every serialized `capture` key are
specified in [`context/capture-slice.md`](context/capture-slice.md). Agents prompt and aggregate;
they never estimate the two human-attested return fields.

## Trigger/dispatch slice

Wires the signal-adapter and dispatch state of
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md),
discovery-first: discover the four signal-surface classes and their transports, wire the DIY floor
(event kick + scheduled drain) as reviewable changes through the one queue-drain entrypoint, advise
plan-gated integrations, and record the `triggers` section (the `surfaces` map + drain cadence) of
the repo-local autonomy binding. Vendor event names and invocation flags live in this slice's
templates, never the contract. The per-surface adapter obligations, the execution-surface
attestation caveat, the admission fail-closed rule, every serialized `triggers` key, and the
[`scripts/check-signal-envelope.mjs`](scripts/check-signal-envelope.mjs) conformance step are
specified in [`context/trigger-dispatch-slice.md`](context/trigger-dispatch-slice.md).

## Guardrail binding resolution

How guardrail policy resolves across the TWO governance surfaces the guardrail contract
splits policy into. This section owns resolution; the [guardrail slice below](#guardrail-slice)
(detect → bind → live-validate → fail-closed) is the action that produces the security binding
this order resolves.

**Two-surface split.** Security-sensitive guardrail axes — isolation bindings with their
runtime markers, merge policy, verification blocking knobs, promotion state, escalation
routes, admission rules and caps — bind ONLY in the security binding document in the
settings-as-code home, outside the blast radius of the agents it governs. Its schema is
contract-owned and ships at
[`schemas/guardrails-security-binding.schema.json`](schemas/guardrails-security-binding.schema.json);
[`scripts/check-security-binding.mjs`](scripts/check-security-binding.mjs) validates a
document (schema shape + the semantic rules the schema cannot express) and, with
`--evidence`, resolves each promotion cell's EFFECTIVE state against a promotion-evidence
source — the bound state is a ceiling contrary evidence lowers without writing the
binding. Non-security axes remap in the additive `guardrails` section of the repo-local
binding: class→label strings (which local label means which work class) and
cost-tier→model names — vocabulary remaps only, never policy content.

**Layered resolution order.** Org-policy-home defaults → settings-as-code per-repo
security binding → repo-local non-security remaps. Later layers refine earlier ones for
NON-SECURITY axes only; no repo-local (agent-writable) value ever supplies or overrides a
security axis.

**Security-binding locator registry.** When settings-as-code is a separate repository,
the org-policy home carries the repo→security-binding-document registry the dispatch seam
resolves each repository's security binding through — one registry, resolvable per repo,
on the org governance surface.

**Agent-unwritable bootstrap for security resolution.** The repo-local `org_policy_home`
pointer is tolerable for non-security defaults only — a repo-writable pointer would let
an agent redirect the whole chain to a forged policy repository carrying a forged
registry, binding, and matching runtime markers. For SECURITY resolution the seam pins
the org-policy-home identity from an agent-unwritable bootstrap: org-level platform
configuration outside repo blast radius (an org-level setting or variable repo agents
cannot write) or the executor's trusted deployment config. Any security resolution that
would depend on a repo-writable pointer — or an unresolvable locator — fail-closes
autonomous dispatch, naming the compliant path (pin the home in org-level configuration
or the executor's deployment config).

**Fail-closed.** An absent or invalid security binding blocks autonomous dispatch —
every signal enqueues human-gated. Documented defaults exist only for non-security axes;
no security axis ever resolves from a documented default or a repo-local surface.

## Guardrail slice

Wires the enforced state of the [guardrail contract](${CLAUDE_PLUGIN_ROOT}/reference/guardrails.md):
detect → bind → live-validate → fail-closed, always detect-diff-reconciling against the org's
EXISTING guardrail surfaces. The [resolution section above](#guardrail-binding-resolution) owns
how bound policy resolves across the two governance surfaces; this slice is the action that
produces the security binding it resolves. Everything lands as reviewable changes; paid scanner
SKUs are advisory + explicit opt-in with cost surfaced.

**This slice PREPARES, never writes the security surface directly.** The security binding lives
in the settings-as-code home, outside the blast radius of the agents it governs — a surface the
running agent cannot write (that is the whole point of the split). So the slice produces the
binding document and its locator-registry entry as REVIEWABLE CHANGES a human lands on the
governance surface (a proposed change on the settings-as-code home, a registry entry on the
org-policy home) — it never mutates the agent-unwritable surface in place. Nothing autonomous
depends on the binding until that human-landed change exists.

1. **Detect substrates per level per machine surface** — for each execution surface the
   trigger/dispatch slice recorded (the same surface ids the security binding's
   `isolation_bindings` key on), inspect what isolation substrates are available at each ladder
   level per the [isolation-ladder leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/isolation-ladder.md):
   an `L2` whole-process OS-sandbox wrap or default-deny-egress container, an `L3` kernel-separated
   VM/microVM or hosted ephemeral executor. Detection is PER SURFACE — a substrate present on one
   surface says nothing about another, and the flat "some surface has L2" answer never satisfies a
   different dispatch surface.
2. **Detect-diff-reconcile against existing guardrail surfaces** — never greenfield-assume, never
   silently overwrite. Before proposing any binding value, read the org's EXISTING guardrail
   surfaces — sandbox/runner configurations, branch protections, review workflows and scanner
   configuration — and DIFF the detected state against them. Where an existing surface already
   encodes a policy (a branch protection rule, a configured scanner, an isolation setting), the
   slice reconciles: it surfaces the diff and proposes the binding that matches or tightens the
   existing surface, and it never overwrites an existing surface as a side effect of binding. A
   pre-existing surface is authoritative input to reconcile against, not a blank field to fill.
3. **Live-validate BEFORE recording** — the empirical probe per substrate class (recipe in
   [`templates/isolation-probe.md`](templates/isolation-probe.md)). A candidate `L2`/`L3`
   substrate is validated by running, INSIDE the boundary, two probes that MUST both fail:
   - a **denied-egress smoke test** — a network fetch to a well-known external host MUST fail
     (a boundary that lets egress through is not an `L2` boundary);
   - a **host-credential-path read attempt** — a read of a host credential path MUST be absent or
     denied (a boundary that leaks host secrets is not an `L2` boundary).

   The checker resolves no DNS and reads no remote host, so it validates the probe's targets against
   operator-configured seams. The egress target checks against `--egress-hosts <host,...>` (a
   configured trusted external target; without it the checker falls back to its
   local/private/encoded/special-use deny lists). Each host credential path checks against
   `--credential-roots <path,...>` DENY-BY-DEFAULT: a filesystem credential entry proves absence only
   when its recorded host-side expansion resolves under a configured trusted root, and with no roots
   configured every filesystem credential entry is untrusted and the level fails closed — a
   cloud-metadata-endpoint route and a well-known credential env token stay bounded closed sets that
   need no allowlist. The allowlist SHAPE (that these seams exist, and their schema) is a
   repo-committed convention; the host-secret-sensitive root VALUES, which reveal where an org's
   credentials live, bind per the deployment's secret-binding classification (a machine/userConfig
   binding), never inlined into the committed binding document.

   Only when the probe transcript proves BOTH failures does the binding for that level on that
   surface land; the transcript's reference is recorded in the level binding's `probe_evidence`
   field (schema-required — a binding without probe evidence is invalid per
   [`scripts/check-security-binding.mjs`](scripts/check-security-binding.mjs)). A binding never
   lands ahead of the probe that proves its boundary.
4. **Bind level → substrate per surface** — record each validated substrate under its surface in
   `isolation_bindings` (surface id → level token → substrate instance + the human-ratified
   `substrate_class` + `probe_evidence` + the non-forgeable `runtime_markers` the dispatch seam
   attests against), plus the merge policy,
   verification-blocking knobs, escalation routes, and admission rules and caps — all on the
   prepared security-binding change, validated by
   [`scripts/check-security-binding.mjs`](scripts/check-security-binding.mjs) against
   [`schemas/guardrails-security-binding.schema.json`](schemas/guardrails-security-binding.schema.json)
   before it is proposed.
5. **Security-review wiring folds in here (no separate capability)** — the security-review policy
   is one part of this single guardrail slice, never a near-duplicate setup capability. Wire the
   [security-review leaf's](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/security-review.md) two
   layers (deterministic scanners + AI security review) into the binding's `verification_blocking`
   knobs, detect-diff-reconciling against the org's existing scanners, review workflows, and branch
   protections. Free-path scanner classes satisfy every blocking obligation on the DEFAULT path —
   zero paid dependencies. Entitlement-gated paid code-scanning SKUs stay advisory + explicit
   opt-in with cost surfaced at opt-in time; an entitlement gap routes the tool to the advisory
   path, never silently passing a blocking layer.
6. **Fail-closed verify** — when NO substrate on a surface reaches the `L2` floor, autonomous
   dispatch is BLOCKED for that surface and the slice names the compliant paths (provision an
   `L2`-capable substrate on the surface, or route the surface's work to a surface that has one,
   or keep the surface human-gated). Silent degrade to a lower level is never conforming. Under
   `dispatch_posture: human-gated-only` a surface with no `L2` binding is the org's DECLARED
   posture, not a defect — the verify reports blocked autonomous dispatch as declared, and the
   binding still validates.

## Routine slice

Wires the standing-routine state of the
[routine catalog](${CLAUDE_PLUGIN_ROOT}/reference/routines.md): a routine is a scheduled
`temporal`-class signal adapter behind the governed queue — never a private execution or merge
path. This slice is discovery-first and detect-diff-reconciles against the org's EXISTING
schedulers and bots. Everything free lands as reviewable changes; paid or preview scheduling
surfaces are advisory + explicit opt-in with cost surfaced. Like the
[guardrail slice](#guardrail-slice) it PREPARES the security surface, never writes it — a
routine's work-class mapping is admission data proposed as a reviewable change on the
settings-as-code home, and nothing dispatches autonomously until a human lands it.

**Routine identity.** A routine is addressed by its IDENTITY: the bare `<class-token>` for a
single-posture class, or `<class-token>/<posture-token>` (kebab-case segments) for a
multi-posture class whose catalog leaf defines more than one work-class posture — e.g.
`doc-freshness-sweep/advisory` and `doc-freshness-sweep/docs-change`,
`ci-health-review/advisory` and `ci-health-review/ci-config-change`,
`dependency-update-wave/mechanical` and `dependency-update-wave/changelog-informed` (the
canonical posture tokens live in the catalog leaves). A multi-posture class binds PER-POSTURE
identities, never its bare token — each posture is a distinct work class and therefore a distinct
identity on a distinct emitting surface. The handler serializes its identity as the envelope's
`signal.routine`, and its platform-attested producer as `signal.producer_identity`, required on
every routine-fired temporal signal.

**Binding-home split by governance sensitivity (the guardrail contract's split).** A routine's
`signal.work_class` is stamped, per
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md)'s
classification rules, from the PROTECTED identity↔surface association the security binding homes —
NOT from the `--routine` argument, the scheduled workflow file, or the emitted `signal.raw_link`,
all of which are CLAIMS an agent-writable job could forge and are never trust anchors. That
association is ADMISSION data: it binds ONLY in the security binding's
`admission.classification.temporal` home
([`schemas/guardrails-security-binding.schema.json`](schemas/guardrails-security-binding.schema.json)),
on the settings-as-code home outside the agents' blast radius — for reconciled existing bots
exactly as for freshly wired routines. Each entry is keyed by routine identity and carries
`{"class": "C1"–"C5", "source_surface": "<surfaces-map id>", "run_link_prefix": "<prefix>",
"producer_identity": "<platform-attested producer ref>"}`: the class the identity's signals
stamp, the one scheduling surface permitted to emit them, the run permalink namespace ratified
for that surface — a platform run URL prefix (`https://…`) for a `ci-cron` surface, or a durable
`file:` or artifact-store URI prefix for a `local-scheduler` surface (weaker authority — a
developer-machine run record or the org's artifact store), which may be repo-scoped and SHARED
across the repo's schedules rather than disjoint per entry — AND the `producer_identity`, the
platform-attested workflow-file or scheduler-unit reference that pins WHICH schedule fired within
that namespace. **One identity per emitting surface** — no two `classification.temporal` entries
may share a `source_surface`, and **producer identities are unique across entries**, so the
producer the platform attests (through the execution-surface attestation and the signal's raw
link and producer reference) is bound to exactly ONE identity. Admission validates the envelope's `(signal.routine, resolved source surface)` pair
against this table AND that `signal.raw_link` falls under the ratified `run_link_prefix` AND that
the attested `signal.producer_identity` equals the entry's ratified `producer_identity` BEFORE
stamping `signal.work_class`; an absent entry, a `source_surface` that does not equal the attested
surface, a raw link outside the ratified prefix, or a producer identity that does not match is
fail-closed human-gated. A swapped `--routine` selector therefore cannot launder high-risk work as
a benign class — claiming a different identity resolves to THAT identity's own surface and
producer, which the platform-attested producer will not match (a shared run-link namespace no
longer distinguishes schedules on its own). A repo-local class source would be the precise agent-writable bypass
the trigger contract's classification obligation forbids. The NON-security keys — cadence,
enablement, surface choice — are the ONLY routine data that lands repo-local: they go in the
additive `routines` section of the repo-local autonomy binding under `.claude/autonomy/` (the same
artifact the `triggers` section lives in), NEVER in the security binding, whose schema carries only
the `admission.classification.temporal` entries. Two artifacts, two validators; the security axis
resolves from the security binding always, non-security refinement repo-local, per the guardrail
resolution order.

1. **Discover scheduling surfaces + budget posture** — interview and inspect which scheduling
   surfaces this org has: CI-cron on the CI-orchestration home, a developer-machine scheduler,
   self-run infrastructure, a vendor-hosted preview scheduler (marked examples, not a closed
   list — research the live surfaces at setup time, never from this doc; preview schedulers are
   moving targets). Record each surface's transport (`poll`, or `push-lifecycle` where the
   surface renews subscriptions) and its `scheduler_class` — the closed discriminator the
   signal-envelope check branches on: `ci-cron` where the surface issues an https run permalink,
   `local-scheduler` where it does not (a durable `file:`/artifact URI stands in). Per-org
   absence of a surface is a binding outcome, never a blocker; budget posture defaults `free`.
2. **Detect-diff-reconcile existing schedulers and bots** — before wiring anything, read what
   already runs: org schedulers, dependency bots, scheduled scanners, existing cron. A live
   agent-judgment bot (a dependency-update bot, a triage bot) IS an instance of a catalog routine
   class, not a rival mechanism: record it in the binding under its routine identity
   (posture-qualified for a multi-posture class) and its surface, reconcile its cadence, and NEVER
   stand up a second mechanism for the same concern. The
   no-agent-session rule holds through reconciliation — a wholly deterministic scheduled check is
   not a routine and keeps running with no agent session, filing work items through the trigger
   adapters; only its judgment-bearing successor, where one exists, is the routine, and a hybrid
   class (e.g. `dependency-update-wave`) reconciles as its split: detection half judgment-free,
   judgment half the routine. A stale or duplicate bot is surfaced as the diff and reconciled, never silently
   overwritten.
3. **Wire free defaults as reviewable changes** — for each enabled routine on a free surface the
   wiring is reviewable changes across role homes, never one agent-written file:
   - the CI-cron handler shape from
     [`templates/routine-definitions.md`](templates/routine-definitions.md) lands on the
     CI-orchestration home (the scheduled job that emits the routine's `temporal` signal into the
     queue);
   - the enabling settings — which routine identities are on, at what cadence, on which surface —
     land as the `routines` section of the repo-local autonomy binding under `.claude/autonomy/`
     (the same artifact as the `triggers` section);
   - the protected identity↔surface association — each routine identity →
     `{class, source_surface, run_link_prefix, producer_identity}`, one entry per identity, no two
     sharing a surface and no two sharing a `producer_identity` —
     lands as the `admission.classification.temporal` change PREPARED for the security binding on
     the settings-as-code home (a separate artifact from the autonomy binding above).

   Every shape enqueues through the trigger contract's `temporal` adapter and the one dispatch
   entrypoint; no routine executes work in its own handler and no second scheduling path is
   created.
4. **Advise paid/preview surfaces** — a vendor-hosted or preview scheduler that carries a
   plan/seat cost is advisory + explicit opt-in, cost surfaced first, never the default path. An
   entitlement gap routes the surface to the advisory step; the free CI-cron/local-scheduler floor
   covers the default path with zero paid dependencies.
5. **Record the binding** — the `routines` section of the repo-local autonomy binding under
   `.claude/autonomy/` (additive, absent-section tolerance, no major bump — the SAME artifact and
   shape as the `triggers` section), NON-security keys only. This section NEVER enters the security
   binding; the ratified `admission.classification.temporal` entries are a separate artifact under
   the security schema and checker.

   | Key | Value |
   |---|---|
   | `surfaces` | object keyed by scheduling-surface id, the SAME shape the [trigger slice](#triggerdispatch-slice)'s `surfaces` map uses (`{"class": "temporal", "transport": "poll"\|"push-lifecycle", "scheduler_class": "ci-cron"\|"local-scheduler", "execution_surface": "<recorded id>"}`; a `local-scheduler` surface using an org artifact store also declares `artifact_schemes`). Record a surface here ONLY when the trigger slice has not already recorded it — [`scripts/check-signal-envelope.mjs`](scripts/check-signal-envelope.mjs)'s resolver merges every section's `surfaces` map and refuses an id recorded in two sections as ambiguous; a routine riding an already-recorded surface REFERENCES its id, it does not re-declare it |
   | `enabled` | object keyed by the FULL routine identity (`<class-token>` or `<class-token>/<posture-token>`) — each entry `{"source_surface": "<surfaces-map id>", "cadence": "<schedule expression or token>", "enabled": <bool>}`; cadence, enablement, and surface choice ONLY. Its `source_surface` MUST agree with the same identity's `source_surface` in the security binding's `admission.classification.temporal` — binding review and the envelope checker catch drift. The class, its `run_link_prefix`, and its `producer_identity` are NOT here; an identity with no protected classification entry, or one whose surface disagrees, stays unclassified and fail-closed human-gated |

6. **Conformance** — the wired state is reached when
   [`scripts/check-signal-envelope.mjs`](scripts/check-signal-envelope.mjs), run with BOTH
   `--binding` at the repo-local autonomy binding (the `routines`/`triggers` surfaces) AND
   `--security-binding` at the security binding (the `admission.classification.temporal` entries),
   confirms `signal.routine` is present, resolves `signal.source_surface` to a recorded surface
   with its temporal raw-link form, and verifies any stamped `signal.work_class` matches the
   protected classification entry for that `(identity, surface)` pair AND that `signal.raw_link`
   falls under that entry's ratified `run_link_prefix` AND that the attested
   `signal.producer_identity` equals that entry's ratified `producer_identity`; a missing
   `signal.routine`, an unresolvable surface, an identity↔surface mismatch, a raw link outside the
   ratified prefix, a `producer_identity` mismatch, or an unclassified class is a finding.

## Runner note

The [runner design pack](${CLAUDE_PLUGIN_ROOT}/reference/runner.md) is bindable-when-born:
until a build trigger fires and the runner-execution home is born, setup records NOTHING
runner-specific — no probe, no wiring, no binding section for the unborn home. The single
exception is escalation notification routes, which already home on the security surface: the
severity axis (`notice`/`attention`/`urgent`) and the personal-push tier are prepared as route
options through the security binding's `escalation_severity`, `escalation_severity_routes`, and
`escalation_ack` keys — a reviewable change on the settings-as-code home like every other
security axis, never repo-local. The route set, its two-step severity resolution, and the
per-class default severities are specified by the
[runner escalation leaf](${CLAUDE_PLUGIN_ROOT}/reference/runner/escalation.md); this note points
there rather than restating them.

## Gotchas

Editing- and run-time failure modes — the two-binding split (repo-local autonomy binding vs the
separate security binding), the spell gate splitting coined hyphenated compounds, and a scheduling
surface recorded in two `surfaces` maps resolving as ambiguous — are catalogued in
[`context/gotchas.md`](context/gotchas.md).

## What this skill does NOT do

- Wire capability slices that have not shipped yet — each lands with its own work package and
  extends this skill (the runner charter execution pack is the next such slice).
- Estimate, impute, or backfill the two human-attested return fields — ever.
- Mutate platform settings, user settings, or `pluginConfigs`.
- Assume the shape of any particular org or fleet — a run against an unknown repo asks or
  defaults; it never guesses silently.
- Recommend or privilege any observability vendor — sink classes only; the deployment picks
  instances.
