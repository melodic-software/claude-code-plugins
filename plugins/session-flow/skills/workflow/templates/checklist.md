# Workflow Checklist

Copy this checklist into the topic's memory-tier slice as `<memory_dir>/<slug>/workflow-checklist.md`
(default `.work/`; resolved per the workflow skill's "Consumer conventions"). Tick each box as the corresponding
stage produces its output. The ticked artifact is the durable proof-of-stage for `/clear` resume
and `/session-flow:retro` analysis.

## Stages

- [ ] 1. Explore: relevant code, tests, and history read → findings noted
- [ ] 2. Research: the claims the work depends on verified against current authoritative sources
- [ ] 3. PRD (conditional): problem, users, success metrics written (SKIP unless the change is
  user-facing, business-driven, and needs alignment)
- [ ] 4. Contract: goal, constraints, acceptance criteria locked (SKIP when intent is already
  crisp from the user's request)
- [ ] 5. Design: design gate passed and the plan's design section written, or a one-line early
  exit recorded with its reason
- [ ] 6. Plan: plan written with phases + verification criteria, user-approved (stress-tested
  when blast radius is wide)
- [ ] 7. Decompose (conditional): tickets published with dependency edges and design excerpts
  (SKIP when the plan is one ticket)
- [ ] 8. Implement: plan executed, incremental validation, commits per green phase
- [ ] 9. Test: affected suite green; new behavior covered
- [ ] 10. Review: diff reviewed against repo conventions; blocking findings resolved
- [ ] 11. Verify: outcome matches intent, with evidence (measurements where improvement is claimed)
- [ ] 12. Retrospective (optional): `/session-flow:retro` run; learnings codified

## Ship: PR lifecycle (after stage 11)

- [ ] PR prep: pre-PR sequence complete (`context/pre-pr.md`)
- [ ] PR created
- [ ] CI green; review comments addressed
- [ ] Merged

## Skip criteria

A stage may be SKIPPED with explicit justification recorded next to its box. Typical skips: stage 4
when intent is already crisp; stages 3 and 7 when their triggers do not hold; stage 9 for doc-only
changes with no behavior delta. Never skip stages 1, 2, 5, 6, 10, or 11 for code changes; stage 5
on work with no design question is its recorded early exit, not a skip.

## How to use

1. At task start, copy this template into the work-artifact location.
2. As each stage produces its output, tick the box. The tick is the commitment that the stage ran
   AND produced its artifact.
3. At `/clear` or session end, the ticked state is durable, so the next session reads the file to
   resume.
4. `/session-flow:retro` analyzes ticks + skips for codification opportunities.
