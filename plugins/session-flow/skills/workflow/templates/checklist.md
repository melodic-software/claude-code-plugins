# Workflow Checklist

Copy this checklist into the topic's memory-tier slice as `.work/<slug>/workflow-checklist.md`
(resolved per the workflow skill's "Consumer conventions"). Tick each box as the corresponding
stage produces its output. The ticked artifact is the durable proof-of-stage for `/clear` resume
and `/retro` analysis.

## Stages

- [ ] 0. Contract — goal, constraints, acceptance criteria locked (SKIP when intent is already
  crisp from the user's request)
- [ ] 1. Explore — relevant code, tests, and history read → findings noted
- [ ] 2. Research — load-bearing claims verified against current authoritative sources
- [ ] 3. Plan — plan written with phases + verification criteria, user-approved (stress-tested
  when blast radius is wide)
- [ ] 4. Implement — plan executed, incremental validation, commits per green phase
- [ ] 5. Test — affected suite green; new behavior covered
- [ ] 6. Review — diff reviewed against repo conventions; blocking findings resolved
- [ ] 7. Verify — outcome matches intent, with evidence (measurements where improvement is claimed)
- [ ] 8. Retrospective — `/retro` run; learnings codified

## PR lifecycle (after step 7)

- [ ] PR prep — pre-PR sequence complete (`context/pre-pr.md`)
- [ ] PR created
- [ ] CI green; review comments addressed
- [ ] Merged

## Skip criteria

A stage may be SKIPPED with explicit justification recorded next to its box. Typical skips: stage 0
when intent is already crisp; stage 5 for doc-only changes with no behavior delta. Never skip
stages 1, 2, 3, 6, or 7 for code changes.

## How to use

1. At task start, copy this template into the work-artifact location.
2. As each stage produces its output, tick the box — the tick is the commitment that the stage ran
   AND produced its artifact.
3. At `/clear` or session end, the ticked state is durable — the next session reads the file to
   resume.
4. `/retro` analyzes ticks + skips for codification opportunities.
