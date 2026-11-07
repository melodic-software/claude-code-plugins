---
description: 'Legacy decompose 14. A PLAN.md Behavior list with two behaviors citing the same criterion: two slices split by each phase''s Delivers line, each carrying AC1 and the Process criteria id AC2, nothing published. two-slices reads the reply for the slice count. Read-only tools, graded on the reply.'
tags: [decompose, slicing, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the Behavior list, the Process criteria line and each phase''s Delivers line, and proposes two draft slices: B1 with AC1 and Phase 1, B2 with AC1 and Phase 2, both also carrying AC2 from Process criteria. The criterion trace maps AC1 and AC2 to both slices. Nothing is published before approval.'
---

/work-items:decompose

The topic is refund-export and its approved PLAN.md reads, under `## Plan`:

```markdown
### Behavior
- B1: Finance staff download one month's refunds as CSV. (AC1)
- B2: Finance staff see the same month's refund total on the export page. (AC1)
Process criteria: AC2

### Phase 1: CSV export [TODO]
**Satisfies:** AC1, AC2
**Delivers:** B1

### Phase 2: Export page total [TODO]
**Satisfies:** AC1
**Delivers:** B2
```

Its criteria are AC1: the export's refunds for a month match the bank statement for that month, and AC2: the PR body links the issue it closes. Draft the breakdown.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
