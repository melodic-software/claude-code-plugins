# Routines

Normative contract for standing scheduled routines: what a routine is, the language that
separates standing from session-scoped repetition, the contract-owned mapping rules that
derive every routine class's guardrail row, and the class catalog as the glance layer. This
document is the hub of a progressive-disclosure contract — the catalog table plus the mapping
rules alone answer "what classes exist, what governs each"; definition depth exists only for
the v1 classes, one leaf per class under `routines/`. All governance is imported by citation
from the [guardrail contract](guardrails.md) and the
[trigger-dispatch contract](trigger-dispatch.md); nothing is redefined here.

## What a routine is

A routine is a scheduled trigger adapter behind the governed work-item queue: a standing
schedule plus a saved task definition that, on each firing, enqueues through the trigger
contract's `temporal` [signal-surface class](trigger-dispatch.md#signal-surface-classes) and
executes only through its [one dispatch entrypoint](trigger-dispatch.md#dispatch). A routine
is never a private execution, merge, or scheduling path. Every
[adapter obligation](trigger-dispatch.md#adapter-obligations) binds it — admission is
enforced at the seam, and the routine's bound definition is what derives the
`signal.work_class` stamp per the
[classification rules](trigger-dispatch.md#work-class-classification) — and the
[guardrail matrix](guardrails.md#the-matrix) governs from the moment the item is queued.

Deterministic checks are never routines: judgment-free date, threshold, and pipeline
mechanics run as plain cron with zero agent tokens, filing work items on failure through the
same trigger adapters. The catalog flags such classes `not-a-routine` — they stay visible as
rows, never silent exclusions.

## Two families of repetition

The contract's ubiquitous language splits repetition into two families. Session-scoped
constructs live and die inside one agent session; standing constructs survive sessions and
fire fresh ones.

| Term | Family | Meaning |
|---|---|---|
| `loop` | session-scoped | repetition on an interval inside one session; dies with the session |
| `goal` | session-scoped | completion condition — the session keeps going until a separate grader judges the condition met or a budget cap trips |
| `batch` | session-scoped | parallel fan-out over decomposed units of one brief; NOT bulk-inference batch APIs (a corrected research conflation) |
| `dynamic workflow` | session-scoped | orchestration whose decomposition and sub-steps the session composes at run time; ends with the session |
| `schedule` | standing | the standing time trigger |
| `routine` | standing | schedule + saved task definition, firing a fresh agent session per run |

Only the standing family is this contract's subject; session-scoped constructs need no
standing governance beyond the session that runs them.

## Trigger taxonomy

Three trigger shapes place a routine class in time. All three enter work through the trigger
contract's signal-surface classes — none is a second scheduling path.

| Trigger | Meaning | Queue entry |
|---|---|---|
| `schedule` | cron-fired cadence; the routine's defining shape | `temporal` surface class |
| `event` | a source emission the routine rides in addition to its cadence | the routine's run is always `temporal` (rule below); the event itself may separately enqueue as an ordinary signal through its own surface class |
| `continuous` | standing monitor | the routine's run is always `temporal` (rule below); a push feed wakes the routine, and where the surface offers no push the `temporal` poll-fallback detector is the conforming form; the feed emission may separately enqueue as an ordinary `channel-feed` signal |

**Routine runs stay temporal — every wake source.** A routine run never enters the queue
through a foreign adapter. Event-riding means the event WAKES the routine's own emitting
scheduling surface — an event trigger on the same ratified schedule surface — and the run
that surface emits is a `temporal`-class signal carrying `signal.routine` under the same
ratified identity, surface, run-link namespace, and `producer_identity` as a schedule-tick run
([classification](trigger-dispatch.md#work-class-classification)). Only the wake source
varies; identity, attestation namespace, producer identity, and classification are invariant. The event itself
may still flow through its own event adapter as an ordinary signal — an advisory landing as
a tracker item is such a signal — but the routine's run is always `temporal`. A continuous
monitor's push feed likewise only wakes the ratified surface; the feed message may enqueue as
an ordinary `channel-feed` signal, but the routine's run is always `temporal`.

## Output contract

Routine output is an advisory report OR a work item filed into the governed queue. Direct
change is never a routine-private capability: it exists only through the merge-policy column
of the [guardrail matrix](guardrails.md#the-matrix) for the class the routine derives.
Governed-queue and tracker writes are permitted `C1` output — scoping in the
[work-classes leaf](guardrails/work-classes.md).

## Mapping rules (catalog to matrix)

The mapping rules are contract-owned so an adopting org can classify a novel routine class
end-to-end — axes to guardrail row to prerequisites — without a contract change. Score the
class on the catalog's axes, then apply the rules below.

### Judgment and output

- Judgment `DET` → not a routine. Plain cron, zero agent tokens; failures file work items
  through trigger adapters. Flagged `not-a-routine` in the catalog.
- Hybrid `DET` detect + `AGT` judgment → split: the detection portion routes to plain cron;
  the judgment portion IS the routine and derives through the `AGT` rules below.
- `AGT` + report → `C1`.
- `AGT` + work item → `C1` (a governed-queue write; no repository mutation).
- `AGT` + direct change → `C2` where the change's truth is mechanically checkable; `C3`
  otherwise.
- `AGT/HUM` → the agent prepares; the disposition is human-gated always (the
  [admission policy](guardrails/admission-policy.md)'s `human-gated` disposition).

### Risk-raising axes

- **Structural blast radius** — a direct change to a structural or configuration surface
  derives `C4`.
- **Input provenance** — a routine consuming attacker-writable external content derives
  `C5`, the untrusted-provenance class. This is a class outcome, not a caveat. The axis keys
  on EXTERNAL content: the `ext` access class, and judgment postures that reason over
  external prose or code such as upstream release notes, changelogs, and third-party package
  contents. Third-party-authored text already inside the org's own tracker and product
  surfaces is admission-governed routine input, not a `C5` trigger.
- **Composition** — when multiple rules match, the derivation composes to the highest-risk
  class (`C5` > `C4` > `C3` > `C2` > `C1`). A structural change driven by attacker-writable
  input derives `C5` and its floor, never `C4`'s lower floor.

### Access to prerequisites

- `repo` — the [`L2` unattended floor](guardrails/isolation-ladder.md#unattended-floor)
  applies; no connector prerequisite.
- `prod`, `product`, `org`, `ext` — a connector is a prerequisite, with the entitlement
  resolved in the org binding; a missing surface or entitlement routes to the advisory path
  per the trigger contract, never a silent degrade.
- External-watch classes read attacker-writable content: the input-provenance rule applies,
  so the read-only class's remaining exfiltration surface
  ([work-classes](guardrails/work-classes.md)) composes to a `C5` class outcome.
- Unattended GUI actuation requires the highest
  [isolation-ladder](guardrails/isolation-ladder.md) tier.

### Routine identity

A routine binds under a routine identity: `<class-token>` for a single-posture class, and
`<class-token>/<posture-token>` for each enabled posture of a class whose derivation yields
portion-split rows (kebab-case segments). A multi-posture class never binds its bare class
token; each posture-qualified identity carries that posture's derived class. The
identity-to-class mapping is admission data on the security binding, each entry bound to its
one emitting scheduling surface — one identity per surface — so the schedule-side selector is
a claim the admission seam validates against the ratified binding, never a trust anchor, for
the same agent-unwritable reason the
[classification obligation](trigger-dispatch.md#work-class-classification) states. Posture
tokens are owned by the class's definition leaf.

## The catalog

One row per class. Judgment: `DET` deterministic · `AGT` agent judgment · `AGT/HUM` agent
prepares, human decides · hybrid rows show the split. Output: `R` report · `WI` work item ·
`DC` direct change. Access: `repo` (incl. CI/tracker) · `prod` · `product` · `ext` · `org`.

| Status | Meaning |
|---|---|
| `v1` | proven manual pattern; definition leaf ships under `routines/` |
| `not-a-routine` | pure deterministic class: plain cron, zero agent tokens |
| join: … | deferred class; it gains a leaf when the named join trigger fires |

| Class | Judgment | Output | Access | Derived row | Status |
|---|---|---|---|---|---|
| **Ops / production** | | | | | |
| alert-triage | AGT | R + WI | prod | C1 | join: telemetry connector exists |
| anomaly-detection | DET (ML detector) | R (alert) | prod | n/a — no agent session | not-a-routine |
| slo-error-budget-review | AGT/HUM | R | prod | C1; disposition human-gated | join: telemetry connector exists |
| alert-noise-review | AGT | R + WI | prod | C1 | join: telemetry connector exists |
| log-review-sweep | AGT | R | prod | C1 | join: telemetry connector exists |
| incident-retro-drafting | AGT | R (draft) | prod | C1 | join: telemetry connector exists |
| postmortem-followup-sweep | hybrid: DET detect → cron; AGT nudge judgment is the routine | R + WI | repo | C1 | join: proven recurring manual pattern |
| on-call-handoff-summary | AGT | R | prod | C1 | join: telemetry connector exists |
| on-call-conflict-resolution | AGT | DC (schedule) | org | C3 (truth not mechanically checkable) | join: org systems connected |
| **Issue lifecycle** | | | | | |
| issue-triage-sweep | AGT | WI + R | repo | C1 | v1 |
| duplicate-detection-sweep | AGT | WI + R | repo | C1 | v1 |
| stale-issue-pr-grooming | DET | DC per policy | repo | n/a — no agent session | not-a-routine |
| backlog-readiness-check | AGT | WI + R | repo | C1 | v1 |
| pr-queue-tending | AGT | R + WI | repo | C1 | v1 |
| flaky-test-quarantine | hybrid: DET detect → cron; AGT root-cause is the routine | WI + DC (quarantine) | repo | C1 (WI); quarantine DC C2 (mechanically checkable) | join: proven recurring manual pattern |
| support-ticket-conversion | AGT/HUM | WI (gated) | product | C1; disposition human-gated | join: analytics/feedback connected |
| **Security / compliance** | | | | | |
| dependency-update-wave | hybrid: DET detect → cron; AGT breakage judgment is the routine | DC (PR) | repo | C2 (CI-mechanical); composes to C5 when judging attacker-writable upstream content | v1 |
| advisory-cve-triage | AGT | R + WI | repo | C1 | v1 |
| secret-scan-review | AGT/HUM | R + WI | repo | C1; disposition human-gated | join: proven recurring manual pattern |
| license-compliance-audit | hybrid: DET scan → cron; AGT edge-case judgment is the routine | R | repo | C1 | join: proven recurring manual pattern |
| sbom-refresh | DET | DC (artifact) | repo | n/a — no agent session | not-a-routine |
| access-review | AGT/HUM | R (evidence pack) | org | C1; disposition human-gated | join: org systems connected |
| base-image-refresh | DET | DC (PR) | repo | n/a — no agent session | not-a-routine |
| malicious-code-scan | AGT | R | repo | C5 (reads attacker-writable third-party code) | join: proven recurring manual pattern |
| **Code quality / knowledge** | | | | | |
| tech-debt-sweep | hybrid: DET recipes → cron; AGT sweep is the routine | WI | repo | C1 (WI); prioritization disposition human-gated | v1 |
| dead-code-sweep | DET detect | DC (review-gated PR) | repo | n/a — no agent session | not-a-routine |
| doc-freshness-sweep | AGT | R + DC (optional docs PR) | repo | C1 (report); optional gated docs-PR portion C3 | v1 |
| coverage-mutation-watch | DET | R (digest/gate) | repo | n/a — no agent session | not-a-routine |
| release-notes-generation | hybrid: DET cut mechanics → cron; AGT narrative is the routine | DC (draft) | repo | C3 (narrative truth not mechanically checkable) | join: proven recurring manual pattern |
| eng-metrics-digest | AGT | R | repo | C1 | v1 |
| knowledge-base-gardening | AGT/HUM | R + WI | repo | C1; disposition human-gated | join: proven recurring manual pattern |
| ci-health-review | AGT | R + WI + DC (optional) | repo | C1 (report/WI); optional direct CI-config change C4 (structural/config surface) | v1 |
| rotating-quality-improver | AGT | DC (targeted PRs) | repo | C3 | join: proven recurring manual pattern |
| cross-artifact-sync | AGT | DC (mirrored PR) | repo (multi) | C3 | join: proven recurring manual pattern |
| **Product / business-adjacent** | | | | | |
| release-cut | DET | DC (version + tag) | repo | n/a — no agent session | not-a-routine |
| deploy-verification | AGT/HUM | R (go/no-go) | prod | C1; disposition human-gated | join: telemetry connector exists |
| voc-theme-digest | AGT | R + WI | product | C1 | join: analytics/feedback connected |
| analytics-anomaly-review | AGT/HUM | R | product | C1; disposition human-gated | join: analytics/feedback connected |
| experiment-readout | AGT/HUM | R | product | C1; disposition human-gated | join: analytics/feedback connected |
| competitive-ecosystem-watch | AGT | R | ext | C5 (attacker-writable external content; read-only exfiltration surface) | join: named intel need |

### v1 leaves

Definition depth for the ten `v1` classes only — every leaf derives its guardrail row through
the mapping rules above, never by hand:

- [issue-triage-sweep](routines/issue-triage-sweep.md)
- [duplicate-detection-sweep](routines/duplicate-detection-sweep.md)
- [backlog-readiness-check](routines/backlog-readiness-check.md)
- [pr-queue-tending](routines/pr-queue-tending.md)
- [doc-freshness-sweep](routines/doc-freshness-sweep.md)
- [dependency-update-wave](routines/dependency-update-wave.md)
- [advisory-cve-triage](routines/advisory-cve-triage.md)
- [tech-debt-sweep](routines/tech-debt-sweep.md)
- [eng-metrics-digest](routines/eng-metrics-digest.md)
- [ci-health-review](routines/ci-health-review.md)

Deferred classes stay catalog rows until their join trigger fires; `not-a-routine` classes
never gain leaves.

## Precedent pointers (non-normative)

Non-normative precedent pointers for the deferred and deterministic rows, stated as shipped
pattern descriptions; the named-product evidence behind each pattern lives in the
routine-catalog research record, one row per class. `v1` classes carry their precedent in
their leaf documents.

- `alert-triage` — per-alert investigation agents shipped across observability platforms,
  event-triggered today
- `anomaly-detection` — continuous statistical/ML detectors built into monitoring platforms
- `slo-error-budget-review` — standing human cadence in the SRE literature's error-budget
  practice
- `alert-noise-review` — standing alert-insight dashboards feeding a human review
- `log-review-sweep` — scheduled log-watch samples in hosted agentic-workflow sample packs
- `incident-retro-drafting` — post-incident draft generation on resolve in
  incident-management platforms
- `postmortem-followup-sweep` — follow-up items auto-exported to trackers and nudged to
  completion by incident-management platforms
- `on-call-handoff-summary` — recipient-tailored handoff summaries in incident-management
  tooling
- `on-call-conflict-resolution` — a GA continuous background agent on a major
  incident-response platform detecting schedule conflicts and coordinating replacements
- `stale-issue-pr-grooming` — deterministic stale-bot policy engines driven by
  date-threshold rules
- `flaky-test-quarantine` — auto-quarantine pipelines at large test fleets and CI-analytics
  services; agent root-cause analysis emerging
- `support-ticket-conversion` — classify-and-escalate support assistants; no verified
  closed loop — an emerging, unverified class
- `secret-scan-review` — validity-checked secret-incident triage workflows in scanning
  platforms
- `license-compliance-audit` — deterministic license scanners with judgment on edge cases;
  precedent depth unverified
- `sbom-refresh` — per-build artifact regeneration mandated by government minimum-elements
  guidance
- `access-review` — compliance-evidence automation with the decision kept human
- `malicious-code-scan` — daily malicious-code-scan and VEX-generation samples in hosted
  agentic-workflow sample packs
- `dead-code-sweep` — dead-code deletion pipelines filing review-gated change requests
  daily at hundred-million-line scale; judgment-bearing triage of its findings belongs to
  the tech-debt sweep
- `coverage-mutation-watch` — coverage threshold gates and nightly mutation-score ratchets
- `release-notes-generation` — deterministic release-cut tooling plus drafted narratives
  flagged for human review
- `knowledge-base-gardening` — weakest precedent of the catalog; wiki and glossary
  maintainer samples in agentic-workflow packs
- `rotating-quality-improver` — daily targeted test, performance, and accessibility
  improver samples in agentic-workflow packs
- `cross-artifact-sync` — mirrored-PR port routines (library port, parallel-SDK sync) in
  hosted routine samples
- `release-cut` — deterministic version-and-tag release pipelines
- `deploy-verification` — analysis-gated canary promotion/rollback plus go/no-go
  verification samples
- `voc-theme-digest` — continuous feedback ingestion with weekly theme digests in
  product-feedback platforms
- `analytics-anomaly-review` — anomaly surfacing with human review in product-analytics
  platforms
- `experiment-readout` — AI experiment summaries with the ship decision kept human
- `competitive-ecosystem-watch` — continuous external-signal monitoring in
  competitive-intelligence platforms; weekly research samples in agentic-workflow packs

## Instruction provenance

A routine's instruction content lives in a version-controlled, reviewable artifact; the
stored prompt is a thin pointer to that artifact, never the instruction body itself. A
prompt carrying pasted prose is non-compliant: it retains no history, and it drifts
invisibly against the repository state each run executes on. The thin pointer names the
artifact and directs the run to execute it; the artifact holds the substance, and its
version-controlled home owns the diff, review, and rollback the stored prompt does not.

The stored prompt is not itself a versioned artifact. Where a scheduling surface holds the
prompt centrally it exposes no prompt history, diff, or rollback, so a routine's behavior
change is auditable only where the pointed-to artifact is versioned — which is why the thin
pointer, not the prompt, is the conforming shape.

Which artifact, and where it lives, is a deployment-owned binding, consistent with the
Hosting stance below. The following are illustrative bindings, not fixed requirements:

- Cloud routines: the artifact is a skill committed to a selected repository's
  `.claude/skills/`, and the stored prompt points to it. The transfer path is a documented
  clone-and-load: each run clones the selected repositories from their default branch and
  loads their committed skills, so a skill living only in a personal store does not reach
  the run and must be committed to the repository (or declared as a repository plugin) to
  bind.
- Claude Desktop scheduled tasks: the artifact is
  `~/.claude/scheduled-tasks/<task>/SKILL.md` tracked under the deployment's dotfiles, and
  the task's prompt points to it.

## Hosting stance

Hosting is a deployment-owned binding. This contract fixes invariants only:

- the queue contract — every routine enqueues through the trigger contract; no second
  execution, merge, or scheduling path;
- the per-class isolation floor — the [matrix](guardrails.md#the-matrix) min-isolation
  column;
- merge-policy caps — including that vendor-hosted
  [executors](trigger-dispatch.md#executor-surface-classes) stay human-gated;
- cost surfaced before any paid binding; no new cost by default.

Budget posture, org shape, and substrate availability are deployment decision inputs.
Profiles — solo-local, CI-hosted, self-run infra, vendor-hosted — are non-normative examples;
deployments mix profiles per class. The contract assumes no machine, org size, or budget.
