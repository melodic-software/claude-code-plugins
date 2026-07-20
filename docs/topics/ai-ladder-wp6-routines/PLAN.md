# ai-ladder-wp6-routines

## Brief

### TLDR

Standing-routines package (T7): catalog doc as a progressive-disclosure hub (class table =
glance layer), contract-tier definition docs for the v1 subset only, contract-owned
catalog-to-matrix mapping rules, and the routine slice of guided-setup. A routine stays a
scheduled trigger adapter behind the governed queue — never a private execution or merge path.

### Goal

Any adopting org can stand up governed background maintenance — the step-3 unlock:
"maintenance and cleanup that used to wait for someone to find the time now runs continuously
in the background" — with every routine's guardrail row derived from catalog axes, free
hosting defaults, and existing org schedulers reconciled rather than duplicated.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Scope: catalog doc (hub-and-leaves — class table with judgment/output/access scores = glance layer) + per-class definition leaf docs for the v1 subset ONLY (non-v1 classes stay table rows with precedent pointers until their join trigger fires) + catalog-to-matrix mapping rules + routine slice of guided-setup. All capability-distribution home. v1 definitions are contract-tier tool-agnostic docs; vendor-binding capability templates are build-stage artifacts. Fleet routine stand-up = /work-items backlog. |
| D2 | Catalog-to-matrix mapping rules are contract-owned (orgs classify new routine classes without republication): judgment DET → not a routine — plain cron, zero agent tokens, failures file work items through trigger adapters; AGT + report → C1; AGT + work-item output → C1 (governed-queue write, no repo mutation); AGT + direct change → C2 where truth is mechanically checkable, C3 otherwise; AGT/HUM → agent prepares, disposition human-gated always. Access axis → prerequisites: repo-scoped = L2 unattended floor; prod/product/org/ext = connector prerequisite + entitlement resolved in the org binding; external-watch classes read attacker-writable content — the read-only class's exfiltration-surface caveat applies; unattended GUI actuation = highest isolation tier. *REFINED 2026-07-18 (WP6/WP7 stress-test F3+F4): (a) hybrid branch — a DET-detect + AGT-judgment class (catalog rows 7/14/16/28, incl. v1 dependency-update-wave) splits: the detection portion routes to plain cron, the judgment portion IS the routine and derives through the AGT rules; the binary DET/AGT reading could not classify hybrids. (b) Pure-DET classes carry an explicit `not-a-routine` catalog flag (rows 2/12/20/22/25/27/34) instead of silent exclusion. (c) Two axes added so derivation reaches the full matrix: input provenance — a routine consuming attacker-writable external content derives C5 (untrusted provenance), upgrading the external-watch caveat to a class outcome; structural blast radius — direct change to structural/config surfaces derives C4. Overlapping matches compose to the highest-risk class (C5 > C4 > C3 > C2 > C1). Without them derivation topped out at C3 and the novel-class acceptance criterion was unmeetable for C4/C5 cases.* |
| D3 | v1 definition doc shape (each leaf): purpose (toil addressed), trigger-taxonomy slot with suggested cadence (org binds values), access scope, output contract (report shape / work-item filing / gated change), guardrail row derived via D2, admission + escalation notes imported from the guardrail contract, precedent pointer. No vendor scheduling detail baked in — surfaces are preview-stage moving targets; setup researches them live. |
| D4 | v1 subset (repo-scoped, agent-judgment, proven manual patterns): issue triage sweep, duplicate-detection sweep, backlog readiness check, PR-queue tending, doc-freshness sweep, dependency update wave, advisory/CVE triage, tech-debt sweep, ~~dead-code sweep~~ eng-metrics digest, CI health review. *CORRECTED 2026-07-18 (review evidence, RESEARCH-routine-catalog row 25): dead-code sweep is classified DET detect — per D2's rule it is not a routine; detection routes to plain cron filing work items through trigger adapters, and any judgment-bearing triage of its findings belongs to the tech-debt sweep. The WP6 architect round confirms the final v1 roster.* Deferred classes keep T7's named join triggers (prod/product/org/ext access, GUI actuation). |
| D5 | Routine slice of guided-setup is discovery-first: interview the org for scheduling surfaces (CI cron, dev machine, self-run infra, vendor-hosted preview) and budget posture; wire free defaults as reviewable changes (CI-cron handler = CI-orchestration home, enabling settings = settings-as-code home); advise paid/preview surfaces with cost surfaced; detect-diff-reconcile EXISTING org schedulers and bots — a live dependency bot or stale bot IS a catalog-class instance: record it in the binding, never stand up a second mechanism for the same concern. |
| D6 | Ubiquitous language imported from the routine contract thread with one correction: batch = session-scoped parallel fan-out over decomposed units (vendor command verified against the official commands doc; research had conflated it with bulk-inference Batch APIs). Contract carries the two-family distinction: session-scoped (loop, goal, batch, dynamic workflow) vs standing (schedule, routine). Routine output = advisory report OR work item into the governed queue; direct change only through the guardrail matrix's merge policy. |
| D7 | Hosting stance imported unchanged (deployment-owned binding): contract fixes invariants only — queue contract, per-class isolation floor, merge-policy caps including hosted-stays-human-gated, cost surfaced before any paid binding. Profiles are non-normative examples; no machine/org-size/budget assumption. |

### Constraints

- Any fleet repo or vendor name in normative contract text is a defect; vendor names appear
  only as marked examples and in binding docs.
- No second execution, merge, or scheduling path: routines enter work through the trigger
  contract's queue and are governed by the guardrail matrix from there.
- Deterministic checks are never routines — no agent tokens on script work.
- No new cost by default; paid/preview scheduling surfaces are advisory + explicit opt-in.
- Boris-alignment is the standing acceptance criterion (no step-skipping, trust before scale).

### Acceptance criteria

- Catalog glance layer alone answers "what classes exist, what governs each" — leaf docs only
  for v1 depth (progressive-disclosure conformance).
- Every v1 leaf derives its guardrail row through the D2 rules; no row is hand-assigned
  outside them.
- Mapping rules let an org classify a novel routine class end-to-end (axes → guardrail row →
  prerequisites) without contract changes.
- Setup slice wires only reviewable changes, reconciles existing schedulers instead of
  duplicating them, and has zero paid dependencies on its default path.
- Research gaps carried visibly: dependency-update-wave precedent detail rests on official
  docs whose page bodies were not all fetched in full (re-verify at architect); support→bug
  conversion class remains emerging/unverified (not in v1); one vendor goal-primitive claim
  unconfirmed (not load-bearing for v1).
- Boris check: step-3 unlock sentence instantiated by the v1 subset running as governed
  background work; "break up your work into loops and routines" cell covered with the
  session-scoped vs standing distinction; step-3 trap honored (catalog-now,
  instantiate-on-trust — v1 dispatch gated by the admission policy and promotion discipline);
  token-efficiency bottleneck addressed (deterministic-stays-cron + cost tiers); step-1
  guardrail untouched.

### Captured assumptions

- The v1 classes' manual patterns remain proven in the first adopting instance (fleet dogfood
  evidence: recurring manual sweeps exist for each).
- Vendor scheduling surfaces remain preview-stage moving targets; contract-tier docs stay
  binding-free and setup researches surfaces live (re-verify at setup time, not bake-in).
- The guardrail matrix (WP5) and trigger contract (WP4) land before or with any v1 routine
  instantiation — routines have no governance path without them.

### Out-of-scope (deferred with triggers)

- Non-v1 class definition leaves — trigger: T7's named join triggers per group (telemetry
  connector, analytics/feedback connected, org systems connected, named intel need, GUI-only
  system + isolation tier).
- Vendor-binding capability templates (routine/workflow files) — build stage, post-architect.
- Fleet routine stand-up + existing-scheduler reconciliation execution — /work-items backlog
  post-graduation.
- Interactive escalation UX for routine-filed items — WP7 (inherited from guardrail package).

### Deferred questions

- Exact class tokens + catalog table serialization — `/architect` (with plugin naming pass).
- Suggested cadence defaults + per-class output templates — `/architect`.
- Leaf-doc file split + glance wording — `/architect`.
- Adapter shapes per scheduling-surface class — `/architect` (live-verified then).

## Plan

Recommendation-locked this round under the user's standing pre-authorization: catalog hub
`reference/routines.md` with v1 definition leaves under `reference/routines/` (one file per
v1 class, kebab-case class tokens below); class tokens for the v1 roster —
`issue-triage-sweep`, `duplicate-detection-sweep`, `backlog-readiness-check`,
`pr-queue-tending`, `doc-freshness-sweep`, `dependency-update-wave`, `advisory-cve-triage`,
`tech-debt-sweep`, `eng-metrics-digest`, `ci-health-review` (ten classes; dead-code sweep
stays off the v1 roster per the D4 correction — the architect-round confirmation the
correction asked for — and appears in the catalog as a `not-a-routine` row; hybrid v1
classes, e.g. `dependency-update-wave`, classify through the D2 hybrid branch: detection
portion cron, judgment portion the routine); catalog table serialization = one markdown table (class token × judgment × output ×
access × derived guardrail row × v1/deferred + join trigger).

Prerequisites: WP4 implementation merged (`reference/trigger-dispatch.md` — routines are
scheduled trigger adapters behind its queue contract) and WP5 implementation merged
(`reference/guardrails.md` — the D2 mapping rules derive rows into its matrix). This package
merges after both.

### Phase 1: Catalog hub + mapping rules [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/routines.md` | Create | The T7 routine contract as the catalog hub: routine definition (a scheduled trigger adapter behind the governed queue — never a private execution/merge path); the two-family ubiquitous language imported per D6 (session-scoped: loop, goal, batch, dynamic workflow; standing: schedule, routine — with the corrected batch definition); trigger taxonomy (schedule / event / continuous); output contract (advisory report OR work item into the governed queue; direct change only through the matrix merge policy); the D2 catalog-to-matrix mapping rules verbatim, INCLUDING the refined axes (DET → plain cron, never a routine — flagged `not-a-routine` in the catalog; hybrid DET-detect + AGT-judgment → split: detection portion cron, judgment portion IS the routine, derived through the AGT rules; AGT+report → C1; AGT+work-item → C1; AGT+direct-change → C2 where mechanically checkable else C3; structural/config-surface direct change → C4; input provenance: attacker-writable external content → C5, the untrusted-provenance class, not a caveat; when multiple rules match, the derivation COMPOSES TO THE HIGHEST-RISK class (C5 > C4 > C3 > C2 > C1 — a structural change driven by attacker-writable input derives C5 and its L3 floor, never C4's lower floor); AGT/HUM → human-gated disposition; access axis → prerequisites incl. L2 floor for repo-scoped, connector+entitlement for prod/product/org/ext, highest tier for unattended GUI actuation — without the C4/C5 axes the Phase 4 untrusted-provenance derivation could not run from the shipped contract); the glance-layer catalog table: all 39 classes as rows (class token, judgment, output, access, derived row, and a status flag — `v1`, a named join trigger, or `not-a-routine` for the seven pure-DET rows incl. dead-code sweep, which stay as rows with their cron/tooling precedent pointers rather than silent exclusions); hybrid rows show the D2 split (detection portion cron, judgment portion the routine); non-v1 rows carry precedent pointers only, no leaves; hosting stance per D7 (invariants only, profiles as non-normative examples). Zero vendor/fleet names in normative text. |

**Sanity Check:**

- `grep -c 'DET' plugins/autonomy/reference/routines.md` ≥ 1 and mapping rules present (`grep -ci 'plain cron' …/routines.md` ≥ 1)
- Catalog rows: table row count = 39 (`grep -cE '^\| [a-z][a-z0-9-]+ \|' plugins/autonomy/reference/routines.md` = 39)
- v1 rows = 10 (`grep -c '| v1 |' plugins/autonomy/reference/routines.md` = 10, or the chosen flag token)
- `not-a-routine` rows = 7 (`grep -c 'not-a-routine' plugins/autonomy/reference/routines.md` ≥ 7); the dead-code-sweep row carries the flag (`grep 'dead-code' plugins/autonomy/reference/routines.md | grep -c 'not-a-routine'` = 1 — flagged, never a silent exclusion, and never a v1 leaf)
- Vendor+fleet deny-list sweep exit 0; lychee lane passes

### Phase 2: v1 definition leaves [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/routines/<class-token>.md` × 10 | Create | One leaf per v1 class, uniform D3 shape: purpose (toil addressed); trigger-taxonomy slot + suggested cadence default (issue-triage-sweep, duplicate-detection-sweep, backlog-readiness-check, pr-queue-tending: daily; doc-freshness-sweep, tech-debt-sweep, ci-health-review: weekly; dependency-update-wave, advisory-cve-triage: weekly with event-riding on advisories; eng-metrics-digest: weekly — all org-bindable values); access scope (repo); output contract (report vs work-item filing per class); guardrail row DERIVED via the D2 rules with the derivation shown (no hand-assigned rows); admission + escalation notes imported by citation from the guardrail contract; precedent pointer (the proven manual pattern). No vendor scheduling detail. |

**Sanity Check:**

- `ls plugins/autonomy/reference/routines/*.md | wc -l` = 10
- Every leaf shows its derivation: `grep -lc 'derived' plugins/autonomy/reference/routines/*.md | wc -l` = 10
- Every leaf names a cadence default: `grep -lc 'cadence' plugins/autonomy/reference/routines/*.md | wc -l` = 10
- Vendor+fleet deny-list sweep exit 0

### Phase 3: Guided-setup routine slice [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Routine slice (D5): interview scheduling surfaces (CI cron, dev machine, self-run infra, vendor-hosted preview) + budget posture; wire free defaults as reviewable changes (CI-cron handler shape = CI-orchestration home role, enabling settings = settings-as-code home role); advise paid/preview surfaces with cost surfaced; DETECT-DIFF-RECONCILE existing org schedulers and bots — a live dependency/stale bot IS a catalog-class instance: record it in the binding (class token + surface), never stand up a second mechanism. Binding home split by governance sensitivity (stress-test F1, the WP5 D2 split): the routine→work-class mapping each temporal signal's `signal.work_class` stamp derives from is ADMISSION data — it lands in the WP5 security binding's `admission.classification` (settings-as-code home, reviewable change, agent-unwritable), for reconciled bots too; only non-security keys (cadence, enablement, surface choice) land as the additive repo-local `routines` section of the schema-versioned binding. A repo-local class source would be the exact agent-writable bypass WP4's classification obligation forbids. Research scheduling surfaces live at setup time (preview-stage moving targets), never from this doc. |
| `plugins/autonomy/skills/setup/templates/routine-definitions.md` | Create | Per-surface-class routine wiring shapes (CI-cron / local scheduler / self-run / vendor-preview as marked examples), parameterized by class token + cadence; every shape enqueues through the trigger contract's temporal adapter — no direct execution path. |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Routine-slice cases: surface interview, free-default wiring, existing-bot reconciliation (record-don't-duplicate), paid-surface advisory refusal-to-default. |
| `plugins/autonomy/README.md` + `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Capability list + description + minor version bump. |

**Sanity Check:**

- `/skill-quality:check` + `validate-evals` pass; `claude plugin validate --strict` exit 0
- `grep -ci 'detect-diff-reconcile' plugins/autonomy/skills/setup/SKILL.md` ≥ 2 (guardrail slice + routine slice each state it)
- `grep -c 'temporal' plugins/autonomy/skills/setup/templates/routine-definitions.md` ≥ 1 (queue-entry via the trigger contract)
- Fleet-name sweep exit 0

### Phase 4: Derivation demonstration + gates [DONE]

Acceptance probe: classify one NOVEL routine class end-to-end using only the shipped mapping
rules (axes → guardrail row → prerequisites) — the acceptance criterion that an org can
classify without contract changes; the chosen novel class MUST be an untrusted-provenance
case (attacker-writable external input) so the probe exercises the D2 provenance axis and
the C5 reach the stress-test found missing, not just the easy C1–C3 path; record the worked
example in the PR body (not in the contract — it is evidence, not normative text). Then the full gate roster
(`validate-plugins.sh`, `run-plugin-tests.sh`, `validate-plugin-contracts.mjs`,
markdown/typos/lychee, `claude plugin validate --strict`, catalog regen). Near-duplicate
audit statement: routines compose the WP4 temporal adapter + WP5 matrix; deterministic checks
stay plain cron; no second scheduling or merge path created.

**Sanity Check:**

- Worked novel-class derivation present in the PR body
- All gate scripts exit 0; catalog in-sync
- Near-duplicate audit statement present in the PR body

## Blast radius

MEDIUM — one plugin's files; the catalog constrains WP7 and every adopting org's background
maintenance, but all governance content is imported from WP4/WP5 by citation, not redefined.
Fully git-revertible.

## Stress-test summary

Fresh-context plan review (WP6+WP7 batch): 10 findings, verdict FIX-THEN-SHIP, WP6's share
folded — F1 (HIGH, cross-package): the routine→class mapping had no security-surface home;
the only binding home named was the repo-local additive-section idiom, which is exactly the
agent-writable class source WP4's classification obligation forbids → the mapping lands in
the WP5 security binding's `admission.classification` (reconciled bots included); only
cadence/enablement/surface stay repo-local. F3 (MED-HIGH): binary DET/AGT mapping could not
classify hybrid classes (a v1 class among them), and two Phase-1 gates were mutually
unsatisfiable (39 rows vs dead-code = 0) → D2 hybrid branch + explicit `not-a-routine`
catalog flag for the seven pure-DET rows; gates reconciled. F4 (MED-HIGH): derivation
reached only C1–C3, silently breaking the novel-class acceptance criterion for C4/C5 →
provenance and structural-blast axes added; the Phase 4 probe now must exercise an
untrusted-provenance case. F8 (LOW) routes to WP5's work-classes leaf (C1 permits
governed-queue writes, no repo mutation).

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — leaves derive through Phase 1's rules; the slice wires
Phase 2's classes; Phase 4 proves Phase 1's rules on a novel class. Cross-package: after the
WP4 and WP5 implementation PRs.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | normative catalog + mapping-rule authoring |
| 2 | main-session | ten uniform leaves, derivation judgment per class |
| 3 | main-session | setup-skill judgment |
| 4 | main-session | derivation probe + gate runs |

## Open questions

- Fleet routine stand-up + existing-scheduler reconciliation execution — /work-items backlog
  post-merge (Brief out-of-scope, trigger recorded).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| v1 roster confirmed at 10 classes (dead-code sweep stays out) | Phase 1 table + Phase 2 leaf count | D4's correction is evidence-backed (RESEARCH-routine-catalog row 25: DET detect); D2's rule excludes DET mechanically |
| Class tokens = kebab-case descriptive names (list in preamble) | Phases 1–2 | Matches every shipped contract token set; one token per catalog row |
| Hub-and-leaves under `reference/routines/` | Phase 1–2 paths | Same layout decision as WP5's guardrail leaves (subdir per hub) |
| Cadence defaults: daily for queue-tending sweeps, weekly for the rest | Phase 2 leaves | Proven manual patterns' observed frequency; org-bindable values, not contract |
| Novel-class derivation as the Phase 4 acceptance probe | Phase 4 | Brief acceptance criterion stated verbatim; cheapest mechanical proof of the mapping rules |

## Handoff to implementation

### User-approval gates

- Any change to the D2 mapping rules or the v1 roster during implementation → STOP
  (user-locked content).
- Any scope expansion beyond the four phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same
commit as each phase.

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-routines`); gates
re-run in full at Phase 4; PR body carries the derivation example + near-duplicate audit
statement + this PLAN in a `<details>` block at close-out.
