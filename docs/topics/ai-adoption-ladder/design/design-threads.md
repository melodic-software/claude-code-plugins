# Design threads — ai-adoption-ladder

## T1: Autonomous-kickoff trigger layer (#240) — RESOLVED 2026-07-17

Decision: the trigger layer is a CONTRACT, not a place — thin per-source signal adapters, each
living where its signal natively lands, all normalizing into the work-item queue (work-items'
existing race-safe lease + AFK/HITL classes), drained by one dispatch entrypoint
(work-items:work autonomous mode, verified: `list-frontier --autonomous` excludes needs-human).
Executor sits BEHIND the contract: claude -p / claude-code-action today, runner repo later (#244
swaps the executor, adapters untouched).

Adapter set today:

- GitHub events → ci-workflows reusable (label/assignment pattern; CONSTRAINT: runner-policy
  admission is a reviewed contract change)
- cron/schedule → routines via /schedule (verified available on plan), including data-source
  polling detectors (artifact step-3: Tag monitors "a channel or a data source" — data-source
  half lands here; tool-version-drift-check is the existing pattern)
- agent-internal → existing skills (handoff --bg, implement-dispatch)

Deferred with trigger:

- Tag channel adapter — Tag is Enterprise/Team-only, Slack-only, beta (verified: Anthropic
  announcement + support docs). Trigger: plan gains Tag or platform expansion lands.

No queue bypass for any signal class — audit trail is the trust loop (Boris step-3 trap:
no agent-count scaling before the loop earns trust).

Rationale anchors: engineering-philosophy.md "one mechanism per concern"; OCP (new signal =
new adapter, no core edit); RESEARCH-headless-agents.md seams (invocation adapter ≠ queue+lease);
keeps #244 runner charter clean either way it resolves.

Verify at implementation: claude-code-action agent-task-mode ergonomics (MEDIUM confidence).

Feeds: #243 guardrail matrix owns dispatch POLICY (which classes auto-dispatch, per-class gates).

## T2: Runtime sandbox bar for autonomy (#245) — RESOLVED 2026-07-17

Decision: tool-agnostic isolation-level ladder + uniform unattended floor, fail-closed.

Ladder (contract vocabulary; instances illustrative, org-supplied per #241 guided-setup pattern):

- L0 worktree + VCS perms only — attended interactive only
- L1 per-command OS sandbox (Bash-only; MCP/hooks/file tools on host) — attended ergonomics
  tier, NOT an autonomy tier
- L2 whole-process OS-enforced boundary + default-deny egress + credential protection —
  MINIMUM for any unattended run (free paths: sandbox-runtime wrap [beta], container w/
  default-deny firewall)
- L3 kernel-separated ephemeral environment (VM/microVM/hosted vendor surface) — untrusted
  repos, policy-required kernel separation

Axes: attendance × input provenance (who can write to what the agent reads). Trigger-source
axis REJECTED (falsified): untrusted content reaches agent-internal runs via repo files, deps,
fetched web — not just external signals.

Fallback where L2 unavailable (e.g. native Windows without WSL2/Docker): FAIL CLOSED —
autonomous dispatch blocked for that surface; guided setup names compliant paths. No silent
degrade (trust-loop leak, Boris step-3 trap; mirrors vendor failIfUnavailable pattern).

Evidence: RESEARCH-sandbox-bar.md (vendor primary falsified original L1-floor proposal:
per-command sandbox "not sufficient for fully unattended runs"). Boris alignment: artifact
guardrail = "agent sandboxing"; L2 is that guardrail implemented at the vendor-stated
unattended bar. Attended multi-worktree workflows untouched.

Feeds: #243 assigns work classes to levels + L3 escalation rules; #244 runner inherits L2+
as its execution substrate requirement.

## T3: Per-work-class guardrail matrix (#243) — RESOLVED 2026-07-17

Decision: five semantic risk classes × five guardrail columns, all in contract vocabulary;
org binding seam maps classes/labels/tiers to local instances (work-items binding-shape
precedent; no tracker/machine/repo-shape assumptions).

Rows (risk-property bundles: blast radius, reversibility, input provenance, verifiability):

- C1 read-only (audits, research, reports — no repo mutation)
- C2 mechanical maintenance (dep bumps, lint/format, sync — deterministic, trivially reversible)
- C3 scoped change (briefed fix/small feature — bounded, tests exist)
- C4 structural (refactors, migrations, contract changes — cross-cutting, hard reversal)
- C5 untrusted-provenance (fork PRs, external contributions, unvetted repos)

Matrix:

| Class | Min isolation (unattended) | Verification | Merge policy | Cost tier | Escalation |
|---|---|---|---|---|---|
| C1 | L2 (exfil surface remains) | output-shape checks | n/a; artifacts via queue audit trail | economy | low |
| C2 | L2 | deterministic blocking | auto-merge ELIGIBLE after per-class promotion trigger; ships human-gated | economy | gate failure → human |
| C3 | L2 | deterministic blocking + AI review (advisory, promotable per #241) | human merge | standard | divergence/failed verify → human |
| C4 | L2 | deterministic + AI + human review mandatory | human merge always | premium | upfront plan approval |
| C5 | L3 | full gates + zero secret exposure | human merge always | standard | always |

- Promotion-trigger pattern (#241) reused per cell; C2 auto-merge only near-term closed-loop
  cell — matches vendor human-merge-gate consensus (closed loop = step 4).
- Cost tiers = contract vocabulary (economy/standard/premium); org binds models. Partially
  covers 2→3 token-efficiency gap.
- Escalation column DIRECTIONAL — mechanism sharpens after #244 runner charter (fog item:
  runner escalation UX).
- AFK/HITL role = dispatch mechanism; class sets default (C1/C2 autonomous-eligible,
  C3 per-item, C4/C5 human-gated).

Boris alignment: step-4 bottleneck verbatim 'enforcing the right guardrails for each type of
work' — matrix is that sentence as a table, built at 2→3 with tightening path defined (no
step-skipping); trust-before-scale via promotion triggers; #241/#245 columns imported
unchanged.

## T4: Autonomous-runner charter (#244) — RESOLVED 2026-07-17

Decision: charter now, build on trigger. Charter locks scope + constraints while the evidence
is fresh; no build before the 2→3 trust loop earns it.

Build trigger (either fires):

- C2 promotion trigger fires (per T3) AND existing executors (claude -p /
  claude-code-action-class surfaces behind the T1 contract) demonstrate a clean autonomous
  drain, OR
- existing executors hit an isolation/concurrency/platform wall the runner uniquely solves.

Scope boundary — queue-contract split (interactive-upstream / autonomous-downstream):

- Plugins own everything interactive (interview → design → architect → decompose → triage
  produce autonomous-eligible items) AND the trigger adapters (T1: adapters live where their
  signals natively land).
- Runner = the autonomous drain side only: lease-claim from the work-item queue, execute in
  isolation, verification gates, merge policy per class, escalation back to humans. The
  runner never decides what to build. Boundary IS the queue contract; runner is one
  executor behind it (T1: swapping executors leaves adapters untouched).

Substrate stance — self-run primary, hosted via adapter:

- Primary substrate = self-operated CLI/SDK surface class — the only class where merge
  policy is ownable (research: every hosted issue-to-PR agent keeps a deliberate
  human-merge-gate). C2 auto-merge promotion (T3) is reachable only self-run.
- Vendor-hosted surfaces remain reachable through the invocation-adapter seam (it covers
  local-CLI and cloud-API shapes) but inherit their human-merge-gate: matrix merge-policy
  column caps at human-gated on hosted. Hosted vendor-managed isolation stays a legitimate
  L3 instance (e.g. C5 work).
- Contract names surface CLASSES (self-operated vs vendor-hosted), never vendors.

Inherited constraints (imported unchanged):

- Execution substrate ≥ L2, fail-closed where unavailable (T2).
- Per-class gates/merge/cost/escalation from the guardrail matrix (T3).
- Queue + lease reused from the work-items race-safe lease + AFK/HITL classes — no second
  claim mechanism (T1; research: no vendor ships a lease protocol, we already have one).
- No queue bypass; audit trail is the trust loop (T1).

Abstraction requirements: the 8 seams (RESEARCH-headless-agents.md synthesis) — invocation
adapter, structured-output envelope, queue+lease, isolation policy, outcome-verification
gate, merge-policy toggle, observability+cost, session/resume+caps.

Anti-goals: set-and-forget framing, ungated autonomy, pull_request_target-class trigger
footguns.

Deferred to design/architect (graduation, not this charter): adopt-vs-reimplement the
composition spine (peer-frameworks recommendation: orchestration+sandbox spine, adapter
layer, merge-queue/escalation lifecycle re-expressed in our vocabulary per absorb
discipline), multi-backend isolation as launch requirement vs deferrable, lifecycle depth,
escalation UX (map fog item), repo/packaging topology.

Boris alignment: build-on-trigger honors the step-3 trap verbatim (no agent-count scaling
before the loop earns trust); queue-drain runner is "let Claude kick off Claude" with the
audit trail intact; self-run substrate is the only path to the step-4 closed loop, chartered
at 2→3 with the tightening path defined — no step-skipping.

Sharpens: T3 escalation column mechanism = the runner's escalation seam (severity/class-routed
per matrix; UX still fog → design stage).

## T5: Return accounting (#246) — RESOLVED 2026-07-17

Decision: in scope for 2→3, shaped as a lightweight convention — no new capability, no new
cost. Boris (thread post 3, verbatim): usage measures activity, not return; return = "would
you have spent engineering effort on this anyway? what would it have cost in manual
eng-hours?"

Three-layer data model:

1. Machine/deterministic — automation cost (tokens/$, wall time; existing session telemetry)
   - lifecycle metadata (tracker timestamps, open→close durations, entity lifecycles —
   definitively calculable from tracker metadata/exports).
2. Human-attested — (a) counterfactual: would-have-done-anyway yes/no/partial;
   (b) manual-effort BAND (<1h / 1–4h / 1–2d / 1w+) — bands, not point estimates.
   SUPERSEDED 2026-07-18 (WP3 architect round, interview-locked, revised same day on
   stress-test evidence): band set corrected to six contiguous bands
   `<1h / 1-4h / 4h-1d / 1d-1w / 1w-1mo / >1mo` — the draft left 4h–1d and 2d–1w unmapped,
   and an open `>1w` top band erased the largest avoided-effort signal. WP3 PLAN.md is the
   governing record.
3. Agent/LLM — prompts for layer 2 at the task boundary; analyzes/aggregates over 1+2;
   NEVER estimates the return fields (models poor at effort estimation). Revisit trigger:
   models proven capable at effort estimation — constraint is conditional, not permanent.

Capture point: task boundary (work-item close / PR merge), tracker-resident record.
Capture scope: autonomous-class work only (classes per T3 matrix); interactive exempt —
prompting friction kills compliance; divergence lives where no human is in the loop.
Expansion trigger: post-#247 aggregate shows spend concentrating in interactive work.
Optional precision graduation: per-class matrix column, only if needed.

Aggregation/reporting transport deferred to #247 — its sink becomes the cost/value join
point.

Rejected shapes: new family inside the measurable-delta verification capability (contract
misfit — counterfactual has no baseline-before-change); standalone capability now (heavier
than the data justifies; graduates later if the convention proves capture happens); fold
into #247 (conflates human capture with machine transport); defer entirely (dataset cannot
be captured retroactively).

Boris alignment: two human fields = his two questions verbatim; usage/return distinction
preserved (telemetry alone never presented as return); convention-before-capability honors
trust-before-scale; step-1 OTel-into-existing-stack guardrail untouched. Vocabulary is
contract-only (work-item tracker, task boundary, autonomous-class).

Deferred to design/architect: prompt wording, band values, tracker field vs comment shape,
cost-join mechanics.

## T6: Telemetry unification (#247) — RESOLVED 2026-07-17

Decision: unify at the CONTRACT layer — standards-only telemetry contract + trace
propagation; sink explicitly out of the contract. Evidence:
RESEARCH-telemetry-unification.md (primary-sourced; falsification pass demoted "semconv
stable" to Release Candidate).

The contract (agnostic on every axis — machine, repo, user, org, tool):

1. Every execution context (interactive session, CI, autonomous runner) emits standard
   OTLP pinned to the OTel CI/CD + VCS semantic conventions (RC as of Jul 2026:
   cicd.pipeline.run.id, cicd.pipeline.result, cicd.pipeline.task.run.result, task types,
   vcs.change.id, vcs.ref.head.revision). Pin upstream vocabulary; never invent parallel
   schema.
2. One minimal custom attribute namespace carries the work-item ID — verified semconv gap
   (no work-item-tracker attribute exists). This is the T5 return-accounting join key.
   SHARPENED 2026-07-18 (WP2 architect round, interview-locked): the attribute is
   `autonomy.work_item.url`, value = the item's canonical web URL in normalized form (native
   short IDs collide across repos); resource-scoped on agent-session emission, span-scoped on
   CI spans. WP2 PLAN.md is the governing record.
3. W3C TRACEPARENT propagates across trigger → CI → agent session: one causal tree.
   Verified: headless agent sessions inherit TRACEPARENT natively. Unification by context
   propagation, not sink merging.

Sink binding is deployment-owned (out of contract): existing observability stack when the
org has one (Boris step-1 guardrail verbatim); free default when none = OTLP file
artifacts + query-on-read (DuckDB-class, emerging pattern with real tooling); running
backend (self-hosted or paid) = explicit opt-in, never default. Zero new cost by default.

Fresh-eyes consequence (user directive: reimplementations of built-ins get scrapped):
local per-machine collector + DuckDB pipeline is ONE conforming sink instance, not
privileged; native agent-CLI OTel export (cost/tokens/tool events, metrics + logs, beta
traces) likely part-duplicates the 8-hook envelope layer. Audit issues file via
/work-items AFTER map graduation, referencing the #247 resolution comment + this thread.

Rejected: shared physical sink as default (infra/cost/secret surface); no unification
(fails step-1 guardrail; starves T5 join + T3/T4 observability seam); mandated reference
backend (binds adopters to one sink; anti-agnostic); human-readable summaries only
(unqueryable, no join).

Deferred to design/architect: custom namespace naming, exact semconv version pin, CI-side
emission mechanics (exporter/action choice), sink adapter shapes, native-vs-hook telemetry
audit scope.

Boris alignment: step-1 guardrail satisfied literally (standard OTel into whatever stack
exists); no step-skipping (contract now, mechanics at build, no speculative backend);
trust loop fed — verification outcomes become queryable promotion evidence (T3 C2); one
trace tree across trigger/CI/agent strengthens the "let Claude kick off Claude" audit
trail (T1/T4).

Sharpens: T5 aggregation join = the work-item correlation attribute; T4 observability+cost
seam = this contract.

## T7: Standing scheduled routines (#242) — RESOLVED 2026-07-17

Decision (three parts). Evidence: RESEARCH-routine-catalog.md (primary-sourced; DORA
falsified as task-taxonomy source; security-section citation patch pending at close).

1. Routine contract: a routine is a scheduled trigger adapter behind the T1 queue
   contract — never a private execution/merge path. Trigger taxonomy: schedule / event /
   continuous (AIOps evidence: shipped agents are mostly event or continuous; scheduled
   agent reviews are frontier). Routine output = advisory report OR work item into the
   governed queue; T3 matrix governs from there. Deterministic checks are NOT routines —
   plain cron, zero agent tokens, file work items on failure via T1 adapters.

2. Catalog: 39 classes / 5 groups (ops-production, issue lifecycle, security-compliance,
   code quality-knowledge, product-business-adjacent), each scored on three governing
   axes — judgment (DET / AGT / AGT-HUM), output shape (report / work item / direct
   change), access (repo / prod / product / ext / org / GUI actuation). Axis mapping does
   the governance: judgment → T3 risk class; output shape → merge policy; access → T2
   isolation floor + connector prerequisites.
   - V1 standing subset (fleet 2→3): repo-scoped AGT classes with proven manual patterns —
     issue triage/dup/readiness sweeps, PR-queue tending, doc-freshness, dependency wave +
     advisory triage, CI health review, eng-metrics digest, tech-debt + dead-code sweeps.
   - Deferred with named triggers: prod-access (alert triage, SLO review, deploy
     verification) → telemetry connector exists; product-access (VoC, analytics anomaly,
     experiment readout) → analytics/feedback connected; org-access (on-call conflict,
     access review) → org systems connected; external watch → named intel need;
     computer-use/GUI actuation → GUI-only system + required isolation tier (unattended
     computer use = highest tier).

3. Hosting: deployment-owned binding. Contract fixes ONLY invariants (queue contract,
   per-class isolation floor, merge-policy caps incl. hosted-stays-human-gated per T4,
   cost surfaced before any paid binding) and decision inputs (budget posture, org shape,
   substrate availability — dev machine free/not-always-on, CI-included free-tier bounded,
   self-run infra paid/controllable, vendor-hosted subscription + preview-stage —
   per-class availability requirement, isolation floor). Profiles (solo-local, CI-hosted,
   self-run infra, vendor-hosted) are non-normative examples; deployments mix per class.
   No machine/org-size/budget assumption in the contract. (Corrected mid-session: an
   earlier self-run-primary default was T4 runner-stance leakage — removed.)

Ubiquitous language (locked): loop = session-scoped repetition, dies with session;
schedule = the standing time trigger; routine = standing scheduled unit (schedule + saved
task definition) firing an agent session; goal = session-scoped completion condition,
keep-going-until-met — verified cross-vendor (two leading agent CLIs, official docs).
Research: routine/playbook are near-synonymous vendor names; dispatch = community jargon,
not contract vocabulary. CORRECTED 2026-07-17 (WP6 round, official /commands doc fetched):
batch = session-scoped parallel fan-out over decomposed units (vendor command /batch —
worktree subagent per unit, PR each), NOT bulk inference (research conflated it with Batch
APIs; Boris step-3 cell names /batch verbatim). Still session-scoped — excluded from the
routine (standing) family on corrected grounds. Vendor
scheduling features bind via the invocation-adapter seam; contract never hard-codes
implementation details (they are preview-stage and shifting).

Rejected: routine-as-execute-and-merge agent (second merge path outside matrix);
everything-is-a-routine incl. deterministic crons (burns tokens on script work); broader
speculative v1 (classes join when a manual pattern proves recurring); minimal
queue-tending-only v1 (leaves proven recurring work manual); vendor-cloud-first hosting
default (preview coupling, cost default, human-gate cap); any fixed hosting default at
all (budget/org/substrate are deployment inputs).

Boris alignment: "break work into loops & routines" instantiated; "let Claude kick off
Claude" stays inside the queue-contract audit trail; catalog-now/instantiate-on-trust
honors the step-3 trap; deterministic-stays-cron + free-defaults preserves cost posture;
no step-skipping.

Deferred to design/architect: per-class routine definitions for the v1 subset, cadences,
report/work-item templates, adapter shapes per vendor surface, catalog-to-matrix row
mapping.
