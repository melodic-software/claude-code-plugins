---
description: Run orchestration workflow for a complex task using multi-agent patterns
---

# Orchestrate Command

Run an orchestration workflow that plans multi-agent execution for a complex task.

## Input

$ARGUMENTS - The task description to orchestrate

## Workflow

1. **Analyze the task** to identify:
   - What reconnaissance is needed (scout phase)
   - What implementation is required (build phase)
   - What verification is needed (review phase)

2. **Design the orchestration plan**:
   - Agent templates to use
   - Phase sequence
   - Dependencies between phases
   - Expected outputs per phase

3. **Output the orchestration plan** in format:

```markdown
## Orchestration Plan

**Task:** [task description]

### Phase 1: Scout

**Agents:** [count] x [template]
**Purpose:** [what to discover]
**Areas:**
- [area 1]
- [area 2]

**Expected Output:** [deliverable]

### Phase 2: Build

**Agents:** [count] x [template]
**Input:** Scout findings
**Changes:**
- [change 1]
- [change 2]

**Expected Output:** [deliverable]

### Phase 3: Review

**Agents:** [count] x [template]
**Criteria:**
- [criterion 1]
- [criterion 2]

**Expected Output:** [deliverable]

### Execution Notes

**Total Agents:** [count]
**Parallel Opportunities:** [phases that can run in parallel]
**SDK Requirement:** This plan requires Claude Agent SDK for actual orchestration

### Agent Commands

[Draft command prompts for each agent]
```

## SDK Note

> **Important:** This command produces an orchestration *plan*. Actual execution of orchestrator patterns with agent creation/deletion requires Claude Agent SDK, not Claude Code subagents.

## Example

```

/orchestrate Add rate limiting to the authentication endpoints
```

## Cross-References

- @three-pillars-orchestration.md - Framework
- @single-interface-pattern.md - Architecture
- @orchestrator-design skill - Design workflow
