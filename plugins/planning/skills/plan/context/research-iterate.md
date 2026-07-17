# Research-Iterate Protocol

When `/devils-advocate` surfaces CRITICAL or HIGH findings that weaken the plan, this protocol guides the feedback loop between planning, stress-testing, and research until the plan achieves HIGH confidence.

## The Loop

```
Plan (Steps 2-3)
  │
  ├── /devils-advocate finds CRITICAL/HIGH issues
  │     │
  │     ├── Targeted research for each issue
  │     │     │
  │     │     └── Update the plan based on new evidence
  │     │           │
  │     │           └── Re-run /devils-advocate on updated plan
  │     │                 │
  │     │                 ├── Issues resolved → Proceed to approval (Step 5)
  │     │                 └── New issues → Loop again
  │     │
  │     └── Issue is a known limitation → Document as accepted risk
  │
  └── No CRITICAL/HIGH issues → Proceed to approval (Step 5)
```

## Per-iteration protocol

### 1. Extract actionable findings

From the `/devils-advocate` output, extract each CRITICAL and HIGH finding. For each:

- What assumption failed?
- What evidence is needed to resolve it?
- Is this a plan flaw (can be fixed) or a fundamental constraint (must be accepted)?

### 2. Research targeted queries

Run targeted research (`/discovery:research` if installed, or the strongest research capability available) with specific queries targeting each finding:

- Include the exact claim that failed
- Include version numbers and context
- Ask for alternatives if the original approach is blocked

### 3. Update the plan

Based on research results:

- **Fix**: modify the plan step that relied on the broken assumption
- **Mitigate**: add a fallback or graceful degradation path
- **Accept**: document the risk explicitly with rationale for accepting it
- **Pivot**: if the approach is fundamentally flawed, draft an alternative approach

### 4. Re-assess

Dispatch `/devils-advocate` to a fresh-context sub-agent on the updated plan — never re-run it inline in the producing context, the same fresh-eyes discipline as the first pass (Step 4). Only the changed sections need deep review — unchanged sections carry forward their previous assessment.

## Guardrails

- **Maximum 3 iterations** before escalating to the user. If 3 rounds of Plan-Stress-Research can't resolve the issues, the approach may need to change entirely — that's a decision for the user, not the loop
- **Each iteration must make progress.** If an iteration produces the same findings as the previous one, stop and escalate. The loop is for refinement, not repetition
- **Track what changed.** Present a brief "Iteration N summary" showing what was found, what was changed, and what remains open. The user should be able to see the plan improving across iterations
- **Don't gold-plate.** MEDIUM and LOW findings from `/devils-advocate` are informational — they don't require research-iterate loops. Only CRITICAL and HIGH findings trigger the loop

## When the loop exits

The loop exits when:

1. **No CRITICAL or HIGH findings remain** — plan is approved for presentation
2. **3 iterations reached** — present remaining risks to user for decision
3. **User intervenes** — user redirects the approach based on intermediate findings
4. **Fundamental constraint discovered** — the plan cannot achieve its goal given current constraints. Present the constraint and alternatives to the user
