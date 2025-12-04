# Trade-offs Guide

This reference provides guidance on when to use prompt improvement and understanding the trade-offs involved.

## Core Trade-off: Quality vs. Efficiency

Prompt improvement increases output quality but typically:

- **Increases token usage** (longer prompts, longer outputs)
- **Increases latency** (more processing required)
- **Increases cost** (more tokens = higher API costs)

Understanding when these trade-offs are worth it is essential.

---

## When to Use Full Prompt Improvement

### Ideal Scenarios

| Scenario | Why It's Worth It |
| ---------- | ------------------ |
| High-stakes decisions | Accuracy more important than speed |
| Complex analysis | Structured reasoning improves accuracy |
| User-facing outputs | Quality directly affects user experience |
| Compliance/audit needs | Documented reasoning required |
| Production applications | Consistency across many runs |
| Classification accuracy | 30%+ accuracy improvements documented |

### Performance Expectations

Based on Anthropic's testing:

- **30% accuracy increase** on multi-label classification
- **100% word count adherence** on summarization
- **~40% reduction** in prompt iteration cycles

---

## When NOT to Use Full Prompt Improvement

### Scenarios to Keep Simple

| Scenario | Why Keep It Simple |
| ---------- | ------------------- |
| Simple factual queries | No reasoning needed |
| Speed-critical applications | Latency matters more |
| Cost-sensitive deployments | Token savings important |
| Internal/development use | Quality bar is lower |
| High-volume processing | Cost scales quickly |
| Trivial tasks | Over-engineering wastes resources |

### Signs of Over-Engineering

- CoT for "What is 2+2?"
- 5 examples for binary classification
- 500-word instructions for simple formatting
- Structured reasoning for factual lookup

---

## Trade-off Decision Matrix

### Quick Reference

| Factor | Simple Prompt | Full Improvement |
| -------- | -------------- | ------------------ |
| Latency requirement | < 1 second | 2-10 seconds OK |
| Cost sensitivity | High | Low |
| Accuracy requirement | Good enough | Critical |
| Task complexity | Low | High |
| Auditability need | None | Required |
| Volume | Very high | Moderate |

### Decision Flow

```text
START
  |
  v
Is task trivial (factual lookup, simple classification)?
  |
  +-- YES --> Use simple prompt
  |
  +-- NO
        |
        v
      Is latency critical (< 1 second)?
        |
        +-- YES --> Minimize CoT, limit examples
        |
        +-- NO
              |
              v
            Is cost a major concern?
              |
              +-- YES --> Use moderate improvement
              |           (basic CoT, 2-3 examples)
              |
              +-- NO
                    |
                    v
                  Is accuracy/quality critical?
                    |
                    +-- YES --> Use full improvement
                    |
                    +-- NO --> Use moderate improvement
```

---

## Optimization Strategies

### Strategy 1: Tiered Prompts

Use different prompt versions for different contexts:

```text
Simple Prompt (fast, cheap):
- Development and testing
- Low-stakes queries
- High-volume processing

Improved Prompt (accurate, slower):
- Production user-facing
- High-stakes decisions
- Compliance requirements
```

### Strategy 2: Progressive Enhancement

Start simple, add complexity only as needed:

```text
Level 1: Task + Format only
Level 2: + 2 examples
Level 3: + Basic CoT
Level 4: + Structured CoT
Level 5: Full improvement
```

Test at each level. Stop when quality is sufficient.

### Strategy 3: Conditional Complexity

Apply improvement selectively:

```python
def select_prompt(input):
    if is_simple(input):
        return simple_prompt
    elif is_moderate(input):
        return moderate_prompt
    else:
        return full_prompt
```

### Strategy 4: Caching

For repeated similar queries:

- Cache improved prompt responses
- Use simpler prompts for variations
- Refresh cache periodically

---

## Cost-Benefit Analysis

### Token Impact Example

| Component | Tokens | Cumulative |
| ----------- | -------- | ------------ |
| Basic task | 50 | 50 |
| + Instructions | +100 | 150 |
| + 3 examples | +300 | 450 |
| + CoT output | +200 | 650 |
| **Total** | | **650** |

A 13x increase from basic to full improvement.

### Cost Calculation

```text
Simple prompt: 50 tokens x 1000 queries = 50,000 tokens
Full prompt: 650 tokens x 1000 queries = 650,000 tokens

At $3/million tokens:
Simple: $0.15
Full: $1.95

Monthly (100,000 queries):
Simple: $15
Full: $195
```

### Break-Even Analysis

```text
If full improvement:
- Reduces errors by 30%
- Error handling costs $1 per error
- Error rate drops from 10% to 7%

Savings: 3,000 fewer errors x $1 = $3,000
Cost increase: $195 - $15 = $180

Net benefit: $2,820/month
```

Calculate your specific break-even point.

---

## Latency Considerations

### Typical Latency Impact

| Prompt Type | Typical Latency |
| ------------- | ----------------- |
| Simple | 0.5-1 second |
| Moderate | 1-3 seconds |
| Full improvement | 3-10 seconds |

### Latency Optimization

If latency matters:

1. **Reduce output length** - Constrain response size
2. **Simplify CoT** - Use Basic instead of Structured
3. **Fewer examples** - 2 instead of 5
4. **Stream responses** - Show output as it generates
5. **Parallel processing** - For batch operations

---

## Task-Specific Recommendations

### Classification Tasks

```text
Binary classification: Moderate improvement
- 2 clear examples (one per class)
- Basic CoT if accuracy critical
- Skip CoT if speed matters

Multi-class classification: Full improvement
- Examples for each class
- Guided CoT for decision criteria
- Worth the investment
```

### Summarization Tasks

```text
Simple summary: Minimal improvement
- Word count constraint
- 1 example showing format

Analytical summary: Moderate improvement
- Criteria for what to include
- 2 examples (short and long docs)

Executive summary: Full improvement
- Structured sections
- Examples with reasoning
- Format strictly specified
```

### Code Tasks

```text
Simple generation: Minimal
- Function signature + description

Code review: Full improvement
- Severity ratings
- Examples of each issue type
- Structured output

Debugging: Full improvement
- Step-by-step analysis
- Multiple hypothesis examples
```

### Data Extraction

```text
Single field extraction: Minimal
- Field name + format

Multi-field extraction: Moderate
- Schema specification
- 1-2 examples

Complex extraction: Full improvement
- Validation rules
- Edge case examples
- NOT FOUND handling
```

---

## Monitoring and Adjustment

### Metrics to Track

| Metric | What It Tells You |
| -------- | ------------------ |
| Accuracy | Is quality sufficient? |
| Latency | Is speed acceptable? |
| Token usage | Is cost manageable? |
| Error rate | Are edge cases handled? |
| User satisfaction | Is output meeting needs? |

### When to Adjust

**Scale up improvement when:**

- Accuracy drops below threshold
- User complaints increase
- Error rate spikes

**Scale down improvement when:**

- Latency becomes problematic
- Costs exceed budget
- Quality is consistently over-spec

---

## Summary: The Right Balance

| Priority | Approach |
| ---------- | ---------- |
| Speed first | Simple prompt, minimal examples |
| Cost first | Moderate improvement, test minimum viable |
| Quality first | Full improvement, accept latency/cost |
| Balanced | Tiered approach, match to context |

**The goal is not maximum improvement but appropriate improvement.**

---

## Related References

- For the improvement workflow, see [../workflows/improvement-workflow.md](../workflows/improvement-workflow.md)
- For common issues, see [common-issues.md](common-issues.md)
- For debugging, see [debugging-guide.md](debugging-guide.md)
