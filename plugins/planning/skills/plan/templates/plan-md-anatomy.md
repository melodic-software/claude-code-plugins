# PLAN.md anatomy

The skeleton of the PLAN.md file [`../SKILL.md`](../SKILL.md) writes at its final step, once the
user has approved the plan, and the status-tag grammar that file carries from then on. This is the
PLAN.md *file* shape; the plan *body* template scaled by task size is a different artifact, at
[`../context/plan-template.md`](../context/plan-template.md).

**PLAN.md anatomy.** PLAN holds Brief + Plan; per-phase status lives in the phase tags (`[TODO]` / `[DOING]` / `[DONE]`):

```markdown
## Brief
<from /planning:interview if applicable — task restatement, scope boundaries, success criteria>

## Plan

### Phase 1: <name> [TODO]
<file-by-file changes, rationale, per-phase sanity-check criteria>

### Phase N: <name> [TODO]
<...>

## Blast radius
<LOW / MEDIUM / HIGH with reasoning>

## Stress-test summary
<Step 4 output, or "Skipped: blast radius LOW, no triggers matched">

## Execution shape
<Step 4.5 output — Wave A/B shape with ALLOWED/FORBIDDEN scope-fencing tables + cost note, OR "fully sequential — phase X gates phase Y" one-liner, PLUS the per-phase routing table (Phase | Surface | Basis). Skipped for single-phase plans>

## Open questions
<anything unresolved at approval time>

## Handoff to implementation

### User-approval gates
<actions implementation MUST surface for confirmation before executing: any [FALLBACK] tags, any scope-expansion proposals, any mid-flight pivots that change acceptance criteria. At each gate, ask or stop + flag. An empty section is valid — small tasks may have zero gates beyond the initial plan approval>

### Execution shape ([EXEC-SHAPE] tagged)
<orchestration choices /planning:plan made: parallel waves OR sequential, the per-phase routing table, agent rosters, ALLOWED/FORBIDDEN scope-fencing tables, sub-topic promotion, sanity-check criteria per phase>

### Mechanical work
<commit boundaries, verification checkpoints, sequential fallback path (when parallel recommended). Standard implementation boilerplate — rarely needs user-specific override>
```

Advance the phase tag (`[TODO]` → `[DOING]` → `[DONE]`) as implementation completes each phase. The tags are what a resuming session reads to know where to continue.
