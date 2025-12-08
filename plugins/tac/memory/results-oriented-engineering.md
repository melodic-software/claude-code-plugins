# Results-Oriented Engineering

Every agent must produce concrete, measurable results.

## The Principle

> Every agent interaction should produce artifacts that can be measured, verified, and aggregated.

Not just "work done" but **what was produced**.

## Result Structure

### Standard Result Format

```json
{
  "consumed_assets": ["file1.ts", "file2.ts"],
  "produced_assets": ["docs/summary.md", "src/new-file.ts"],
  "summary": "Created architecture documentation from analysis",
  "status": "completed",
  "metrics": {
    "files_read": 5,
    "files_written": 2,
    "lines_added": 150,
    "tokens_used": 12500
  }
}
```markdown

### Result Components

| Component | Purpose |
| ----------- | --------- |
| **consumed_assets** | Files read, APIs called, resources used |
| **produced_assets** | Files created, modified, or generated |
| **summary** | Human-readable description of work |
| **status** | completed, failed, partial |
| **metrics** | Quantitative measurements |

## Why Results Matter

### For Observability

Without concrete results:

- Can't verify work was done
- Can't measure quality
- Can't aggregate across agents
- Can't improve over time

With concrete results:

- Clear evidence of completion
- Quality can be assessed
- Results aggregate cleanly
- Metrics drive improvement

### For Orchestration

Orchestrator needs results to:

- Know when agent is done
- Decide next steps
- Aggregate into final report
- Verify task completion

## Agent Output Patterns

### Scout Agent Results

```markdown
## Scout Report

**Task:** Analyze authentication module

### Consumed Assets
- src/auth/login.ts
- src/auth/session.ts
- src/auth/middleware.ts

### Findings
1. Current pattern uses JWT tokens
2. Session management is stateless
3. Rate limiting is missing

### Recommendations
1. Add rate limiting middleware
2. Implement token refresh
3. Add audit logging

**Status:** Completed
```markdown

### Builder Agent Results

```markdown
## Build Report

**Task:** Implement rate limiting

### Consumed Assets
- Scout report
- src/auth/middleware.ts
- package.json

### Produced Assets
- src/auth/rate-limit.ts (created)
- src/auth/middleware.ts (modified)
- tests/rate-limit.test.ts (created)

### Changes Summary
- Created rate limiting middleware
- Integrated with auth pipeline
- Added tests (5/5 passing)

**Status:** Completed
```markdown

### Reviewer Agent Results

```markdown
## Review Report

**Task:** Verify rate limiting implementation

### Consumed Assets
- Build report
- Git diff (src/auth/*)
- Test results

### Findings by Risk

**Blocker:**
None

**High Risk:**
- Missing TypeScript types on config object

**Medium Risk:**
- Default rate limit may be too permissive

**Low Risk:**
- Consider adding JSDoc comments

### Verdict
Implementation is acceptable with minor fixes recommended.

**Status:** Completed with recommendations
```markdown

## Aggregation Pattern

### Multi-Agent Result Aggregation

```markdown
## Orchestrator Final Report

**Task:** Add rate limiting to authentication

### Phase 1: Scout
- Agents deployed: 1
- Duration: 45s
- Files analyzed: 5

### Phase 2: Build
- Agents deployed: 1
- Duration: 2m 30s
- Files created: 2
- Files modified: 1

### Phase 3: Review
- Agents deployed: 1
- Duration: 30s
- Issues found: 0 blockers, 1 high, 1 medium

### Summary
Rate limiting successfully implemented and reviewed.
Total duration: 3m 45s
Total cost: $0.15

### All Produced Assets
- src/auth/rate-limit.ts
- src/auth/middleware.ts
- tests/rate-limit.test.ts
```markdown

## Metrics to Track

### Per-Agent Metrics

| Metric | Purpose |
| -------- | --------- |
| Duration | Time to completion |
| Token usage | Resource consumption |
| Files consumed | Input scope |
| Files produced | Output scope |
| Tool calls | Execution complexity |
| Cost | Financial impact |

### Aggregate Metrics

| Metric | Purpose |
| -------- | --------- |
| Total agents | Scale of orchestration |
| Total duration | End-to-end time |
| Total cost | Financial total |
| Success rate | Reliability |
| Coverage | Scope of work |

## Best Practices

### For Agent Prompts

Include output format:

```text
After completing analysis, provide results in this format:

## Results

### Consumed Assets
[List files read]

### Findings
[Numbered list]

### Recommendations
[Actionable items]

### Status
[completed/failed/partial]
```markdown

### For Orchestrators

Request structured results:

```text
Command the scout agent with:
"Analyze X and provide results including:
- Files consumed
- Key findings
- Recommendations
- Status"
```markdown

## Key Insight

> "Results-oriented engineering ensures every agent interaction produces measurable value. If you can't show what was produced, you can't verify the work was done."

## Cross-References

- @three-pillars-orchestration.md - Observability pillar
- @multi-agent-observability skill - Metrics tracking
- @agent-lifecycle-crud.md - Lifecycle management
