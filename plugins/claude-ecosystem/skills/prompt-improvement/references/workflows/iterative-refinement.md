# Iterative Refinement Workflow

This reference provides guidance on multi-pass prompt improvement with feedback integration.

## Overview

Iterative refinement extends the 4-step improvement workflow by incorporating feedback loops. Each iteration targets specific aspects of the prompt based on observed issues or user feedback.

## When to Use Iterative Refinement

Use iterative refinement when:

1. **Initial improvement produces mixed results** - Some aspects work well, others need adjustment
2. **User provides specific feedback** - "The reasoning is too verbose" or "Examples don't cover edge cases"
3. **Testing reveals gaps** - Certain inputs produce unexpected outputs
4. **Convergence not reached** - Output quality varies significantly across inputs

## The Iteration Cycle

```text
┌─────────────────────────────────────────────────┐
│                                                 │
│  ┌─────────────┐     ┌─────────────┐           │
│  │  Improved   │────►│   Test      │           │
│  │   Prompt    │     │   Prompt    │           │
│  └─────────────┘     └──────┬──────┘           │
│         ▲                   │                  │
│         │                   ▼                  │
│  ┌──────┴──────┐     ┌─────────────┐           │
│  │   Refine    │◄────│  Collect    │           │
│  │   Prompt    │     │  Feedback   │           │
│  └─────────────┘     └─────────────┘           │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## First Pass: Full 4-Step Improvement

Apply the complete [4-step improvement workflow](improvement-workflow.md):

1. Example Identification
2. Initial Draft (XML structure)
3. Chain of Thought Refinement
4. Example Enhancement

This establishes the baseline improved prompt.

---

## Subsequent Passes: Targeted Refinement

After the first pass, focus each iteration on specific aspects.

### Clarity Pass

**Focus:** Instruction precision and unambiguity

**Checklist:**

- [ ] Are task boundaries clearly defined?
- [ ] Are edge cases explicitly addressed?
- [ ] Is the scope of the task unambiguous?
- [ ] Are constraints clearly stated?

**Query docs-management:**

```text
Find documentation about being clear and direct in prompts
```

### Chain of Thought Pass

**Focus:** Reasoning depth and structure

**Checklist:**

- [ ] Is the reasoning level appropriate for complexity?
- [ ] Are thinking steps specific to the task?
- [ ] Does the thinking structure match output requirements?
- [ ] Is there too much or too little reasoning?

**Query docs-management:**

```text
Find documentation about chain of thought prompting depth and structure
```

### Example Quality Pass

**Focus:** Example coverage and demonstration

**Checklist:**

- [ ] Do examples cover diverse scenarios?
- [ ] Do examples demonstrate edge cases?
- [ ] Is reasoning visible in examples?
- [ ] Do examples match the expected output format?

**Query docs-management:**

```text
Find documentation about multishot prompting example quality
```

### Output Format Pass

**Focus:** Response structure and consistency

**Checklist:**

- [ ] Is the output format explicitly specified?
- [ ] Does Claude consistently follow the format?
- [ ] Is the format appropriate for the use case?
- [ ] Consider prefill technique for format enforcement

**Query docs-management:**

```text
Find documentation about prefilling Claude's response for output control
```

---

## Feedback Integration

### Types of Feedback

**Explicit Feedback:**

- User corrections: "The summary should be shorter"
- Specific issues: "It doesn't handle multi-language inputs"
- Format changes: "I need JSON output instead of markdown"

**Implicit Feedback:**

- Test results: Accuracy drops on certain input types
- Consistency issues: Output format varies between runs
- Missing coverage: Certain scenarios produce poor results

### Feedback-to-Action Mapping

| Feedback Type | Action |
| --------------- | -------- |
| "Too verbose" | Reduce CoT level, add brevity constraint |
| "Missing cases" | Add examples for uncovered scenarios |
| "Wrong format" | Strengthen formatting section, add prefill |
| "Inconsistent" | Add more explicit constraints, add examples |
| "Too slow" | Reduce CoT, simplify structure |
| "Inaccurate" | Increase CoT, add verification steps |

---

## Convergence Criteria

Stop iterating when:

1. **Quality threshold met** - Outputs meet acceptance criteria
2. **Diminishing returns** - Changes produce marginal improvement
3. **Stability achieved** - Outputs are consistent across inputs
4. **User satisfaction** - Stakeholder approves results

### Warning Signs to Continue Iterating

- Output quality varies significantly between runs
- Certain input types consistently fail
- Format compliance is inconsistent
- User identifies recurring issues

---

## Iteration Best Practices

### One Focus Per Pass

**Good:** "This pass focuses only on example quality"
**Bad:** "This pass fixes examples, adds constraints, and changes format"

### Document Changes

Track what changed in each iteration:

```text
Iteration 1: Added XML structure, basic CoT
Iteration 2: Increased CoT depth for edge cases
Iteration 3: Added 2 examples for multi-language inputs
Iteration 4: Strengthened output format constraints
```

### Preserve What Works

If something is working well, don't change it:

- Lock in successful examples
- Preserve effective constraints
- Keep working formatting specifications

### Test After Each Iteration

Before moving to the next iteration:

1. Run the improved prompt against test inputs
2. Compare results to previous iteration
3. Document improvements and regressions
4. Decide on next focus area

---

## Common Iteration Patterns

### Pattern 1: CoT Calibration

```text
Pass 1: Add basic CoT ("think step-by-step")
Test: Too shallow for complex inputs
Pass 2: Add guided CoT with specific steps
Test: Good for complex, too verbose for simple
Pass 3: Add conditional CoT based on input complexity
Test: Balanced across input types
```

### Pattern 2: Example Expansion

```text
Pass 1: Start with 2 representative examples
Test: Fails on edge cases
Pass 2: Add 2 edge case examples
Test: Handles edges but unclear on ambiguous inputs
Pass 3: Add 1 ambiguous input example with explicit reasoning
Test: Handles all scenarios consistently
```

### Pattern 3: Format Enforcement

```text
Pass 1: Specify format in <formatting> section
Test: Mostly compliant but sometimes adds preamble
Pass 2: Add "Output only the specified format" constraint
Test: Still occasional preamble
Pass 3: Add prefill to force format start
Test: 100% format compliance
```

---

## Maximum Iterations

**Recommended:** 3-5 iterations maximum

If more than 5 iterations are needed:

1. Reassess the task definition
2. Consider breaking into subtasks
3. Check if the task is achievable with prompting
4. Consult docs for alternative approaches

**Query docs-management:**

```text
Find documentation about chaining complex prompts for stronger performance
```

---

## Next Steps

After convergence:

1. **Document final prompt** - Save with version notes
2. **Create test suite** - Preserve inputs used for testing
3. **Consider trade-offs** - See [tradeoffs-guide.md](../troubleshooting/tradeoffs-guide.md)
4. **Monitor in production** - Watch for drift or new edge cases
