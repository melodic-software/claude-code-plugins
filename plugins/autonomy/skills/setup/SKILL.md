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
   from the environment; interactive sessions deliberately ignore inbound trace context.
   Traces stay beta behind `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`; the slice treats spans as
   optional and never depends on beta span shapes.
4. **Record the binding** — sink class, endpoint or artifact path, and the semconv pin land
   as the `telemetry` section of the schema-versioned binding.
5. **Conformance** — run
   [`scripts/check-emission-conformance.mjs`](scripts/check-emission-conformance.mjs) against
   produced OTLP JSON-lines to verify the pinned `schemaUrl` and the join attribute before
   declaring the emitting state reached.

## Return-accounting capture slice

Wires the capture-enabled state of
[`${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md`](${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md),
discovery-first. Everything wireable lands as reviewable changes; GUI-only or
entitlement-gated surfaces get advisory steps with cost surfaced.

1. **Detect the tracker class and close-flow surface** — which tracker the org's work items
   live in, whether it supports native custom fields at the org's entitlement, and where the
   task-boundary close flow is machine-editable (close-triggered workflow, tracker
   automation).
2. **WIRE where machine-editable + reviewable** — a close-triggered snippet
   ([`templates/return-capture.md`](templates/return-capture.md)) posting the UNATTESTED
   record + the attestation request addressed to the accountable human; the close flow never
   blocks. Native-field write where entitled AND provenance-verifiable per the contract's
   record-integrity rule — setup verifies, before selecting `native_fields`, that record-field
   writes are ACL-restricted to the bound automation identity or that the tracker exposes a
   queryable field-audit trail attributing writes; entitlement alone never selects the
   surface, because unverifiable field authorship would let a manual edit pass as an
   authentic attestation — the marker-keyed structured comment otherwise (the universal
   floor, which carries authorship structurally). Entitlement is
   detected at the org's plan level and does NOT confirm the complete v1 record field set is
   provisioned and attached on the item surface — a disclosed v1 limitation this slice does
   not detect: a tracker entitled for custom fields yet missing one or more of the v1 record
   fields cannot hold a conforming record on native fields, so full-field-set
   discovery/provisioning is future work; the universal comment floor stays conforming
   regardless. The trigger is
   GATED to autonomous-class work (the convention's capture scope): the snippet fires only
   when ALL THREE hold — the closing item carries the tracker binding's autonomous-eligible
   role label (the class-scope discriminator; the label marks pickup eligibility, not that
   the work was actually executed autonomously), AND the close event's actor is the bound
   automation identity (the execution-evidence discriminator; proves the closing action
   itself was autonomous), AND the closure outcome is COMPLETED/delivered — a not-planned,
   cancelled, or duplicate closure never captures, even when the automation performs it
   (nothing was delivered, so a record would assert autonomous completion of undone work). Neither alone suffices: the label without automation-actor
   closure would let a human who completes and closes an eligible item post a false
   autonomous record; the automation actor without the label would let interactive items
   the bot closes leak into capture. An unlabeled item, or one closed by any other actor,
   never enters capture (interactive work, and human-closed eligible work, both stay
   exempt). Label-plus-automation-actor closure is itself a PROXY for execution evidence,
   not a bound dispatch record: a close action run by the automation identity after a human
   performed the underlying work is not distinguished from one following genuine autonomous
   work by this gate alone. A first-class dispatch/execution-provenance signal is future
   work the guardrail matrix owns — this interim gate is deliberately the cheapest signal
   available today, not a claim of proof, and the discriminator recorded here is the interim
   boundary, not a parallel class vocabulary. The class-scope label gate resolves the
   autonomous-eligible label from the work-items tracker binding; the standalone path (no
   such binding) has no source for that label and the `capture` binding carries no
   label-mapping key — a disclosed v1 limitation: on that path setup neither assumes a
   default label nor silently omits the gate, so standalone gated capture stays advisory
   until an equivalent label/marker convention is bound, which is future work.
3. **WIRE the reply-triggered attestation handler where machine-editable** — a companion
   comment-created event handler, wired the same reviewable way as the close trigger (a
   native-field-change trigger surface is NOT a substitute: the only defined human input is
   the reply — `partial, 1-4h` or the `attest:` form — and v1 defines no native field-edit
   submission protocol carrying the two values, so a tracker with field-change automation
   but no comment-created surface routes to the ADVISE step like any other
   reply-triggerless tracker): on a new reply, check the reply's actor against the record's
   `attestation_owner` snapshot (resolved once at close; never re-resolved from a mutable
   source, per the contract), require the contract's reply-correlation rule (the event responds to the
   recorded `attestation_request`, or carries the flat-tracker `attest:` token — an
   incidental parseable comment never attests), and on a parseable reply carrying both
   values, upsert the SAME attested record
   (not a second contract — this is the one attestation upsert, wired from its own trigger
   surface) — branched by `record_surface`: on the comment floor, find the marker comment
   AUTHORED BY THE BOUND AUTOMATION IDENTITY and edit it in place (the lookup filters by
   author per the record-integrity rule — a foreign-posted marker is ignored, never
   selected or allowed to shadow the real record — and the bot-authored marker's absence
   enforces the contract's attestation-never-creates rule structurally: no close-time
   record, nothing to edit); on native fields there is no
   marker, but the same rule binds — the handler MUST first verify the close-time
   UNATTESTED v1 record is already present on the item's fields (written by the close
   trigger, which owns the eligibility gate) and treat its absence as inadmissible; where
   the surface was selected on the audit-trail alternative (fields not ACL-restricted),
   presence is not enough — the handler confirms through the trail that the bound
   automation identity created the record AND authored every subsequent revision of the
   record fields (any field-writer could forge a conforming unattested set, or alter an
   existing one — `attestation_owner`, `counterfactual` — after creation; a record with any
   non-automation revision is non-conforming and rejected before the owner snapshot is
   trusted) — only then writing the attested fields directly on that same item (the
   fields are scoped 1:1 to the closing item, so no lookup beyond that verification is
   needed). Where the tracker offers no reply-triggered surface (no comment webhook, a
   plan/tier limit), this step routes through the ADVISE step below instead of silently
   wiring only the close half and calling capture complete.
4. **Route comment writes through the bound tracker adapter's documented comment mechanics
   where a work-item-tracker binding is present** (comments are provider-specific mechanics
   there, not a race-safe seam — only coordination claims are race-safe; no marker upsert
   primitive exists to reuse). The marker-keyed upsert and its attestation-preserving dedupe
   rule are THIS contract's own obligations and apply identically on both paths; the
   standalone snippet differs only in posting directly, and both paths carry the contract's
   stated create-create race rule.
5. **ADVISE where GUI-only or entitlement-gated** — org-gated native fields, plan-gated
   automation: steps + cost surfaced, explicit opt-in. Private-repo close- and
   reply-triggered runs draw metered CI minutes — surfaced on the wire path.
6. **Attestation routing** — the binding records the accountable-human routing per class:
   the requester-identity source for ordinary (requester-carrying) items — which
   tracker-class-specific identity IS the requester (item author, a named custom field);
   never guessed from `tracker_class` alone — and the standing attestation owner (or
   attestation-exempt marking) for requester-less classes. Setup VALIDATES that every
   declared `standing_owner` is a human platform account distinct from
   `automation_identity`, and the close trigger applies the contract's human-owner rule to
   each resolution: a bot/app or automation-matching identity produces no owned record —
   route to the class's standing owner, else that item's capture stays advisory
   (self-attestation would bypass the never-estimate rule). An attestation-exempt class's close trigger posts NEITHER the
   unattested record NOR the attestation request — `return-accounting.md` forbids a
   perpetually-unattested default, so an exempt class's cost is reported separately,
   outside this record schema entirely.
7. **Record the binding** — the `capture` section of the schema-versioned binding (additive,
   like the telemetry section), with these serialized keys:

   | Key | Value |
   |---|---|
   | `tracker_class` | string, the detected tracker class |
   | `record_surface` | `native_fields` \| `comment` — which surface step 2 wired |
   | `automation_identity` | the bound automation's platform identity — checked by step 2's trigger gate and by `return-accounting.md`'s record-integrity rule; MAY be null (undiscoverable and not yet interviewed — never invented, same as `roles`) |
   | `requester_source` | how the accountable requester's platform identity resolves from an ordinary (requester-carrying) item in this tracker class — a tracker-specific identity source such as the item-author field or a named custom field; step 3's reply handler addresses the attestation request to it and validates the attesting actor against it; MAY be null (same ladder) — unbound means the actor check for ordinary items cannot be wired, so their attestation stays unwired and reported, never guessed |
   | `routing` | object keyed by a per-surface identifier for each requester-less recurring surface (standing routines, scheduled sweeps) — the bound work-item tracker's own recurring-schedule row id where that binding exists, else an identifier the setup interview asks for and persists. The key must be resolvable FROM THE CLOSING ITEM per the contract's routing rule: setup verifies the surface's filing template stamps the identifier on each item it files (item-body marker, label, or field — the stamp mechanism recorded alongside the entry), wires the stamp in as a reviewable change where the template lacks it, and leaves the entry unwired-and-reported where the surface cannot stamp (never title-match correlation); each entry is `{"standing_owner": "<platform-identity>", "role": "reviewer" \| "maintainer" \| "other"}` (`role` optional, default `other` — the value the reply handler derives `attestor_role` from on a standing-owner match, per the contract's derivation rule) or `{"attestation_exempt": true}`. A class with a requester needs no entry — the requester IS the routing, resolved through `requester_source`; the whole key MAY be absent when the org has no requester-less autonomous-eligible class yet |

   A binding missing the `capture` section has not wired this slice (absent-section
   tolerance, same as telemetry). `tracker_class` and `record_surface` land once step 1
   detects them; `automation_identity`, `requester_source`, and `routing` follow the SAME
   convention-resolution ladder as every other binding value (config present → use it;
   absent → infer, but ONLY from a signal that verifies the value's defining property;
   cannot infer → interview when `apply` runs interactively, else record null/unbound) —
   NEVER invented. For `requester_source` the tracker's documented item-author semantics
   qualify as such a signal. For `automation_identity` — a TRUST ANCHOR — usage history
   never qualifies: a recent close-event actor may be a human maintainer or an unrelated
   integration, and persisting it would make the close-actor gate pass for human-closed
   items, asserting autonomous completion falsely; only provider-verifiable identity
   metadata (the platform marks the account as an app/bot identity) or an explicit
   configured/interviewed value binds it. Unbound values are never a reason to block a
   non-interactive run or leave the section silently unwired: an unbound
   `automation_identity` means step 2's trigger gate cannot fire yet, and an unbound
   `requester_source` means ordinary-item capture stays ADVISORY on BOTH halves — the close
   trigger too, not just the reply handler, since a close-time record requires the resolved
   `attestation_owner` snapshot and an addressed request (an unowned record could never be
   attested); requester-less surfaces with resolved routing entries may still wire — each
   unbound value is reported, not hidden.

## Trigger/dispatch slice

Wires the signal-adapter and dispatch state of
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md),
discovery-first. Everything lands as reviewable changes; plan-gated surfaces are advisory +
explicit opt-in with cost surfaced. Vendor event names and invocation flags live in THIS
slice and its templates — the contract stays surface-class vocabulary only.

1. **Discover signal surfaces per class** — interview + repo/org inspection for which of the
   contract's four surface classes exist here, the transport each surface actually offers
   (`push` / `push-lifecycle` / `poll`), and entitlements. Per-org absence of a class is a
   binding outcome, never a blocker; an entitlement gap routes that surface to the advisory
   step. The contract's carried research gaps are re-verified at wire time against current
   vendor docs (fresh-docs mandate), not assumed still true.
2. **Wire the DIY floor as reviewable changes** — the kick and the drain:
   - *Kick* (`tracker-vcs-event`): a platform event workflow on the tracker/VCS host running
     the adapter shape from
     [`templates/trigger-adapters.md`](templates/trigger-adapters.md). Marked example, on
     the GitHub Actions class of CI: `issues` (types `labeled`, `assigned`),
     `issue_comment` (type `created`) for @-mention forms, `pull_request` for PR events —
     all verified against the official events reference at wire time; event-trigger
     workflows must exist on the default branch to fire.
   - *Drain* (`temporal`): a scheduled workflow invoking the queue drain. Marked example:
     `schedule` cron (shortest interval 5 minutes; runs may be delayed under load; public
     repos auto-disable schedules after 60 days without activity — surface both caveats)
     plus `workflow_dispatch` for manual kicks. Poll-detector backstops for
     `push-lifecycle` wirings ride the same scheduled surface.
   - *`channel-feed`* (where wanted): a chat-platform bot + events subscription, or a plain
     inbound webhook receiver, normalizing into the same adapter shape — DIY floor only;
     vendor-hosted channel agents are step 3's advisory path.
   - *`agent-internal`*: no wiring — sessions file follow-up work through the queue seam
     directly; the slice records the surface as active and states the `signal.parent_item`
     provenance obligation.
   - *Executor invocation* (marked example, self-operated CLI class): headless `claude -p`
     with `--bare` for deterministic CI context, tool allowlisting via `--allowedTools` /
     `--permission-mode` — verified against the official headless reference at wire time.
3. **Advise plan-gated native integrations** — vendor-hosted channel agents and native
   tracker automations that carry a plan/seat cost: steps + cost surfaced, explicit opt-in,
   never the default path. Zero paid dependencies on the default path.
4. **Bind the drain cadence** — default hourly, org override recorded in the binding. The
   drain funnels into the work-item queue capability's autonomous drain mode via the
   invocation-adapter seam — one entrypoint, no second dispatch mechanism; the seam's
   race-safe lease makes concurrent kicks harmless.
5. **Record execution surfaces** — EVERY kick/drain wiring records its named execution
   surface id, the same id the guardrail security binding's per-surface isolation entries
   key on. The recorded id is repo-local (agent-writable) convenience only: per the
   contract's execution-surface attestation rule, the admission/executor seam derives the
   ACTUAL surface identity from platform-attested runtime metadata and verifies it against
   the recorded id — a mismatch, an unattestable surface, or a surface without an L2+
   isolation binding fail-closes to human-gated. The slice states this next to every
   recorded id so no reader mistakes the record for the enforcement.
6. **Admission enforcement wiring** — every adapter shape points at the guardrail admission
   seam (the admission policy bound on the org's security governance surface). With NO
   admission binding present the wiring fail-closes: every signal enqueues human-gated,
   never dropped, never auto-dispatched. This slice wires the enforcement point; it never
   defines policy content.
7. **Record the binding** — the `triggers` section of the schema-versioned binding
   (additive, absent-section tolerance, no major bump), with these serialized keys:

   | Key | Value |
   |---|---|
   | `surfaces` | object keyed by surface id — each entry `{"class": "<surface-class token>", "transport": "push"\|"push-lifecycle"\|"poll", "scheduler_class": "ci-cron"\|"local-scheduler", "execution_surface": "<recorded execution-surface id>"}`; `scheduler_class` applies to temporal surfaces only and is the discriminator `signal.raw_link` form validation branches on. Any later additive section that records scheduling surfaces (routines) uses the same `surfaces` map shape, so envelope validation resolves `signal.source_surface` against every section uniformly |
   | `drain` | `{"cadence": "<schedule expression or token, default hourly>", "execution_surface": "<recorded execution-surface id>"}` |

8. **Conformance** — run
   [`scripts/check-signal-envelope.mjs`](scripts/check-signal-envelope.mjs) against a queued
   item's body (with `--binding` pointing at the resolved binding) to verify the envelope
   marker record before declaring the wired state reached.

## What this skill does NOT do

- Wire capability slices that have not shipped yet (guardrail matrix, routines) — each lands
  with its own work package and extends this skill.
- Estimate, impute, or backfill the two human-attested return fields — ever.
- Mutate platform settings, user settings, or `pluginConfigs`.
- Assume the shape of any particular org or fleet — a run against an unknown repo asks or
  defaults; it never guesses silently.
- Recommend or privilege any observability vendor — sink classes only; the deployment picks
  instances.
