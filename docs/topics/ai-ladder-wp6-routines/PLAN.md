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
| D2 | Catalog-to-matrix mapping rules are contract-owned (orgs classify new routine classes without republication): judgment DET → not a routine — plain cron, zero agent tokens, failures file work items through trigger adapters; AGT + report → C1; AGT + work-item output → C1 (governed-queue write, no repo mutation); AGT + direct change → C2 where truth is mechanically checkable, C3 otherwise; AGT/HUM → agent prepares, disposition human-gated always. Access axis → prerequisites: repo-scoped = L2 unattended floor; prod/product/org/ext = connector prerequisite + entitlement resolved in the org binding; external-watch classes read attacker-writable content — the read-only class's exfiltration-surface caveat applies; unattended GUI actuation = highest isolation tier. |
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

(unfilled — /architect)
