---
description: Show current context window state and consumption analysis
---

# Context Status

Show current context window state and consumption analysis.

## Instructions

You are analyzing the current context window state.

### Step 1: Measure Context

Use the `/context` command to get current context window state.

Report the metrics:

- Current token consumption
- Percentage of window used
- Warning indicators

### Step 2: Analyze Consumption

Break down what's consuming context:

- System prompt estimate
- Tool definitions estimate
- Conversation history
- Files read in this session
- Recent tool results

### Step 3: Health Assessment

Assess context health:

| Utilization | Status | Recommendation |
| ------------- | -------- | ---------------- |
| <50% | Healthy | Continue working |
| 50-70% | Watch | Monitor for bloat |
| 70-85% | Caution | Consider delegation or fresh instance |
| >85% | Action Required | Start fresh instance |

### Step 4: Report

## Output

Provide status report:

```markdown
## Context Status Report

**Utilization:** XX% (XXXXXX / XXXXXX tokens)
**Status:** [Healthy/Watch/Caution/Action Required]

### Consumption Breakdown
- System + Tools: ~XX%
- Conversation: ~XX%
- Files Read: ~XX%
- Tool Results: ~XX%

### Recommendations
- [Specific recommendations based on state]

### Context Health Indicators
- [ ] Fresh instance (low history)
- [ ] Focused context (relevant files only)
- [ ] Controlled outputs (minimal verbosity)
```

## Notes

- This command helps monitor context for elite context engineering
- Use before complex operations to ensure headroom
- If approaching limits, consider @reduce-delegate-framework skill
- See @context-layers.md for understanding context composition
