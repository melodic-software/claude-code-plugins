# PLAN.md anatomy

The skeleton of the PLAN.md file [`../SKILL.md`](../SKILL.md) writes at its final step, once the
user has approved the plan, and the status-tag grammar that file carries from then on. This is the
PLAN.md *file* shape; the plan *body* template scaled by task size is a different artifact, at
[`../context/plan-template.md`](../context/plan-template.md).

**PLAN.md anatomy.** PLAN holds Brief + Design + Plan; per-phase status lives in the phase tags (`[TODO]` / `[DOING]` / `[DONE]`):

```markdown
## Brief
<the Brief `/planning:interview` writes, in its Brief template's shape, kept as written except for criterion ids added per ../context/plan-template.md "Criterion ids". With no interview: a minimal Brief (Problem, Goal with its three lines, Out-of-scope) or one line `No Brief: <reason>`, per plan Step 1>

## Design
<written by /planning:design-handoff when the design gate passes; /planning:plan keeps it as written. Omit for work with no design stage>

### Module layout
<modules or packages, what goes where, dependency direction>

### Contracts
<interfaces, type shapes, signatures, typed-artifact blocks, quoted>

### Variation verdicts
<per variation point and axis the design considered: abstract now, contain now, or leave inline; the seam or containing module; the reason. Every external integration has a row>

### Conventions followed
<repository paths of the existing patterns, rules, and ADRs this design follows>

Net new: <each part with no existing pattern to follow, and why none fits; or `none`>
Challenges a pattern: <each existing pattern this design departs from or questions, its path, and the reason; or `none`>

## Plan

Citations checked at: <the full commit SHA check-plan-citations.sh printed as `commit=` at Step 4.7; every `path:line` in this file resolves at it>

### Goal
<which Brief Problem it serves, What / Why / Done when, and the Brief's three Goal lines quoted verbatim>

### Acceptance criteria
<only when the plan adds criteria the Brief lacks: `- AC<n>: <criterion>`, numbered after the Brief's ids; omit otherwise>

### Load-bearing assumptions
<Assumption | Source | Falsifying check | Response if false: one row per Brief Captured assumption written `<assumption>: revisit if <trigger>` (not the Quality bar, Variation intent or override lines) and per assumption the plan adds; the check names a phase Sanity Check; the response is Minor, Moderate or Major>

### Alternatives Considered
<Alternative | Why rejected | Switch condition>

### Risks and Mitigations
<Risk | Likelihood | Impact | Mitigation>

### Decisions made (gate-passed)
<Decision | What it changes in the plan | Basis (evidence) | Source, per ../context/tag-decisions.md "Presentation contract"; a deferred Brief question the plan resolved has Source `deferred Q<N>`>

### Phase 1: <name> [TODO]
**Satisfies:** <the acceptance criterion ids this phase satisfies, e.g. AC1, AC3; per ../context/plan-template.md "Criterion ids">
<file-by-file changes, rationale, per-phase sanity-check criteria>

### Phase N: <name> [TODO]
<...>

## Blast radius
<LOW / MEDIUM / HIGH with reasoning>

## Stress-test summary
<Step 4 output, or "Skipped: blast radius LOW, no triggers matched">

## Execution shape
<Step 4.5 output — Wave A/B shape with ALLOWED/FORBIDDEN scope-fencing tables + cost note, OR "fully sequential — phase X gates phase Y" one-liner, PLUS the per-phase routing table (Phase | Surface | Model | Basis), Model one of sonnet / opus / frontier. Skipped for single-phase plans>

## Open questions
<anything unresolved at approval time>

## Handoff to implementation

Approval: <attended: approved by <who> on <date>; unattended: standing mandate <which>, granted by <who> in <where>, review surface <e.g. the PR>>
Reader depth: <guardrails, standard or step-by-step, and the layer that supplied it; written at the first publish or paste>

### User-approval gates
<actions implementation MUST surface for confirmation before executing: any [FALLBACK] tags, any scope-expansion proposals, any mid-flight pivots that change acceptance criteria. At each gate, ask or stop + flag. An empty section is valid — small tasks may have zero gates beyond the initial plan approval>

### Execution shape ([EXEC-SHAPE] tagged)
<orchestration choices /planning:plan made: parallel waves OR sequential, the per-phase routing table, agent rosters, ALLOWED/FORBIDDEN scope-fencing tables, sub-topic promotion, sanity-check criteria per phase>

### Mechanical work
<commit boundaries, verification checkpoints, sequential fallback path (when parallel recommended). Standard implementation boilerplate — rarely needs user-specific override>
```

The `## Plan` sections before the first phase take their bodies from [`../context/plan-template.md`](../context/plan-template.md) "Full Template". A smaller plan drops what its scale omits but keeps Goal, and keeps the assumptions table whenever the Brief captured any.

An early-exit design (`design-resolution.md`) writes `## Design` as one line naming the early
exit and its reason; a Tier B early exit adds a `### Contracts` subsection quoting its type sketch. `## Design` is how the design decisions reach a cleared session, a dispatched
worker's brief, and the published plan; the design directory itself is never published. A phase
cites the subsection it implements rather than paraphrasing it.

Advance the phase tag (`[TODO]` → `[DOING]` → `[DONE]`) as implementation completes each phase. The tags are what a resuming session reads to know where to continue.

## Reader-depth renders

The copy published to the work item or pasted into the pull request carries the depth
`plan_reader` resolves ([`../SKILL.md`](../SKILL.md) "Reader depth"). `step-by-step` publishes
PLAN.md itself. A reduced depth writes a derived file beside it, `PLAN.<depth>.md`, rebuilt from
PLAN.md before every publish and never edited by hand; PLAN.md stays whole. The derived file holds,
in order:

1. One line naming the depth and its reader, e.g. `Guardrails: follow these constraints; the steps are yours.` or `Standard: these constraints and the order of work; the details are yours.`
2. `## Brief` as PLAN.md has it. A pipeline intent check reads the published plan's Brief as the acceptance criteria, so no depth drops it.
3. `## Design` as PLAN.md has it, including `### Conventions followed` with its `Net new:` and `Challenges a pattern:` lines. With no `## Design` section: one line saying the plan has no design stage.
4. `standard` only: `## Phase outline`, each `### Phase N:` heading copied as one line with its status tag.
5. The `Approval:` and `Reader depth:` lines, copied unchanged.

Sections are copied, never reworded, so the published copy cannot drift from the approved plan.
