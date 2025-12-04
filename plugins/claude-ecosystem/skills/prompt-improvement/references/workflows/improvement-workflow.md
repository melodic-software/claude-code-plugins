# The 4-Step Improvement Workflow

This reference provides the detailed workflow for improving prompts using Anthropic's prompt improver methodology.

## Overview

The prompt improver enhances prompts through a structured 4-step process that transforms basic prompts into high-performance templates with clear structure, reasoning instructions, and enriched examples.

## Prerequisites

Before starting:

1. Have the original prompt to improve
2. Understand the task the prompt is trying to accomplish
3. (Optional) Gather feedback on current issues with outputs
4. (Optional) Collect example inputs and ideal outputs

## Step 1: Example Identification

### Goal

Locate and extract any existing examples from the prompt template.

### Process

1. **Scan the prompt** for any input/output pairs
2. **Note the format** of existing examples (inline, structured, etc.)
3. **Identify gaps** - are examples missing entirely?
4. **Extract examples** for later enhancement

### Quality Check

- [ ] All existing examples have been identified
- [ ] Example format has been documented
- [ ] Missing examples have been noted

### If No Examples Exist

Consider generating test cases:

- See [test-case-generation.md](test-case-generation.md) for guidance
- Use synthetic inputs that represent real use cases
- Draft ideal outputs that demonstrate expected behavior

---

## Step 2: Initial Draft

### Goal

Create a structured template with clear sections and XML tags.

### Process

1. **Identify prompt components:**
   - Task definition
   - Context/background
   - Input data
   - Output requirements
   - Constraints/rules

2. **Apply XML structure:**

```xml
<instructions>
[Task definition and behavioral guidelines]
</instructions>

<context>
[Background information - optional if task is self-explanatory]
</context>

[Variable input sections with appropriate tags]

<formatting>
[Output format specification]
</formatting>
```

1. **Query docs-management for tag guidance:**

```text
Find documentation about XML tags for structuring prompts
```

### Quality Check

- [ ] All prompt components are wrapped in appropriate tags
- [ ] Tags are consistently named throughout
- [ ] Variable sections are clearly marked
- [ ] Output format is explicitly specified

### Common Tag Assignments

| Component | Recommended Tags |
| ----------- | ----------------- |
| Task instructions | `<instructions>`, `<task>` |
| Background info | `<context>`, `<background>` |
| Input data | `<document>`, `<data>`, `<input>` |
| Rules/constraints | `<rules>`, `<constraints>` |
| Output format | `<formatting>`, `<output_format>` |
| Examples | `<examples>`, `<example>` |

---

## Step 3: Chain of Thought Refinement

### Goal

Add and refine detailed reasoning instructions that guide Claude's thinking process.

### Process

1. **Identify reasoning requirements:**
   - What analysis is needed?
   - What steps should Claude take?
   - What considerations are important?

2. **Choose CoT level:**

   **Basic CoT:** Simple instruction to think

   ```text
   Think step-by-step before providing your answer.
   ```

   **Guided CoT:** Specific reasoning steps

   ```text
   Before answering:
   1. Identify the key elements of the question
   2. Consider relevant context
   3. Analyze potential approaches
   4. Select the best approach with reasoning
   ```

   **Structured CoT:** XML-tagged thinking

   ```text
   First, analyze the problem in <thinking> tags.
   Include your reasoning process and considerations.
   Then provide your final answer in <answer> tags.
   ```

3. **Query docs-management for CoT guidance:**

```text
Find documentation about chain of thought prompting and step-by-step reasoning
```

### Quality Check

- [ ] Reasoning instructions match task complexity
- [ ] Thinking process is explicitly requested
- [ ] Output structure separates thinking from answer
- [ ] Reasoning steps are specific to the task

### CoT Level Selection Guide

| Task Type | Recommended CoT Level |
| ----------- | ---------------------- |
| Simple factual | None or Basic |
| Analysis/comparison | Guided |
| Complex reasoning | Structured |
| Multi-step problem | Structured with steps |

---

## Step 4: Example Enhancement

### Goal

Update examples to demonstrate the new reasoning process.

### Process

1. **Transform existing examples:**
   - Add `<thinking>` sections showing reasoning
   - Show step-by-step analysis
   - Connect reasoning to final output

2. **Structure enhanced examples:**

```xml
<example>
  <input>
    [The input for this example]
  </input>
  <thinking>
    Step 1: [First consideration]
    Step 2: [Analysis]
    Step 3: [Conclusion]
  </thinking>
  <output>
    [The expected output]
  </output>
</example>
```

1. **Ensure alignment:**
   - Examples follow the same structure as instructions
   - Reasoning matches the guided steps
   - Output format matches formatting specification

### Quality Check

- [ ] All examples include reasoning process
- [ ] Reasoning demonstrates the expected approach
- [ ] Examples cover different scenarios/edge cases
- [ ] Output format is consistent across examples

### Example Enhancement Principles

**Before Enhancement:**

```text
Input: Classify this email as spam or not spam.
Email: "You've won $1 million! Click here to claim."
Output: spam
```

**After Enhancement:**

```xml
<example>
  <input>
    Classify this email as spam or not spam.
    Email: "You've won $1 million! Click here to claim."
  </input>
  <thinking>
    Analyzing the email for spam indicators:
    1. Unrealistic promise ("won $1 million")
    2. Urgency/call to action ("Click here")
    3. No prior lottery participation mentioned
    4. Classic phishing pattern

    Conclusion: Multiple strong spam indicators present.
  </thinking>
  <output>
    spam
  </output>
</example>
```

---

## Final Quality Checklist

After completing all 4 steps, verify:

### Structure

- [ ] Clear XML tag organization
- [ ] Consistent tag naming
- [ ] Logical component ordering

### Instructions

- [ ] Task is clearly defined
- [ ] Constraints are explicit
- [ ] Output format is specified

### Reasoning

- [ ] Chain of thought is appropriate for complexity
- [ ] Thinking process is explicitly structured
- [ ] Answer format is clearly separated

### Examples

- [ ] Examples demonstrate expected reasoning
- [ ] Multiple scenarios are covered
- [ ] Format matches instructions

---

## Common Pitfalls to Avoid

1. **Over-engineering simple tasks** - Not every prompt needs full CoT
2. **Inconsistent tag usage** - Use same tags throughout
3. **Missing output format** - Always specify expected format
4. **Examples without reasoning** - Enhanced examples should show thinking
5. **Too many examples** - 3-5 diverse examples usually sufficient

---

## Next Steps

After improvement:

1. **Test the improved prompt** with sample inputs
2. **Iterate with feedback** - See [iterative-refinement.md](iterative-refinement.md)
3. **Consider trade-offs** - See [../troubleshooting/tradeoffs-guide.md](../troubleshooting/tradeoffs-guide.md)
