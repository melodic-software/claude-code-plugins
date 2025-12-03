# Test Case Generation

This reference provides guidance on creating examples when none exist in the original prompt.

## Overview

When improving a prompt that lacks examples, generating test cases is essential. Examples teach Claude HOW to reason and WHAT format to produce, making them critical for prompt quality.

## When to Generate Test Cases

Generate test cases when:

1. **Original prompt has no examples** - Starting from scratch
2. **Examples are insufficient** - Only 1 example or all examples are similar
3. **Edge cases are missing** - No examples for boundary conditions
4. **New scenarios emerge** - Requirements change or expand

---

## The Test Case Generation Process

### Step 1: Identify Input Categories

Before generating test cases, categorize the types of inputs your prompt will receive.

**Questions to ask:**

- What are the typical/expected inputs?
- What are the edge cases or boundary conditions?
- What are the potential error or invalid inputs?
- What variations exist within valid inputs?

**Example for a classification task:**

```text
Categories:
1. Clear positive cases
2. Clear negative cases
3. Ambiguous/borderline cases
4. Multi-label cases
5. Invalid/malformed inputs
```

### Step 2: Generate Representative Inputs

Create synthetic inputs that cover each category.

**Principles:**

- **Realistic:** Inputs should resemble actual use cases
- **Diverse:** Cover different scenarios and variations
- **Challenging:** Include cases that test reasoning
- **Minimal:** Each input tests a specific aspect

**Example inputs for email classification:**

```text
1. Clear spam: "You've won $1 million! Click here now!"
2. Clear not-spam: "Meeting reminder: Project sync at 3pm tomorrow"
3. Ambiguous: "Special offer for valued customers - 20% off"
4. Multi-aspect: "Invoice attached. Please review urgently!"
5. Edge case: "[Empty email body]"
```

### Step 3: Draft Ideal Outputs

For each input, write the ideal output Claude should produce.

**Process:**

1. Apply the task's criteria to the input
2. Determine the correct classification/answer
3. Write the output in the expected format
4. Include reasoning if CoT is used

**Example ideal output:**

```xml
<example>
  <input>
    Email: "You've won $1 million! Click here to claim."
  </input>
  <thinking>
    Analyzing for spam indicators:
    1. Unrealistic promise ("won $1 million")
    2. Urgency without context ("Click here")
    3. No established relationship
    4. Classic lottery scam pattern

    Conclusion: Multiple strong spam indicators present.
  </thinking>
  <output>
    Classification: spam
    Confidence: high
    Reason: Multiple spam indicators including unrealistic promises and urgency.
  </output>
</example>
```

### Step 4: Validate and Refine

Test the generated examples by running them through the prompt.

**Validation checklist:**

- [ ] Does Claude produce similar outputs to ideal?
- [ ] Is reasoning consistent with examples?
- [ ] Are edge cases handled correctly?
- [ ] Is format consistent across examples?

---

## Coverage Strategies

### Minimum Viable Coverage

For simple tasks, aim for:

- **3 examples minimum**
- 1 typical positive case
- 1 typical negative case
- 1 edge case

### Comprehensive Coverage

For complex tasks, aim for:

- **5-7 examples**
- 2 typical cases (positive/negative or different categories)
- 2 edge cases (boundaries, ambiguities)
- 1-2 challenging cases (require nuanced reasoning)
- 1 format demonstration (shows exact expected output)

### Coverage Matrix

| Category | Simple Task | Medium Task | Complex Task |
|----------|-------------|-------------|--------------|
| Typical cases | 2 | 3 | 4 |
| Edge cases | 1 | 2 | 3 |
| Challenging | 0 | 1 | 2 |
| Format demo | 1 | 1 | 1 |
| **Total** | **3-4** | **5-6** | **7-10** |

---

## Example Enhancement Techniques

### Adding Reasoning Steps

Transform basic examples into enhanced examples:

**Before:**

```text
Input: "Meeting at 3pm tomorrow"
Output: not-spam
```

**After:**

```xml
<example>
  <input>Meeting at 3pm tomorrow</input>
  <thinking>
    Analyzing the email:
    1. Content: Standard meeting reminder
    2. Tone: Professional, informational
    3. No suspicious links or urgent calls to action
    4. Appears to be normal business communication
  </thinking>
  <output>not-spam</output>
</example>
```

### Showing Edge Case Reasoning

For ambiguous cases, explicitly show the decision process:

```xml
<example>
  <input>Limited time offer! 20% off for our customers.</input>
  <thinking>
    This email has mixed signals:

    Spam indicators:
    - "Limited time offer" is promotional language
    - Uses urgency ("Limited time")

    Not-spam indicators:
    - Addresses "our customers" (established relationship)
    - Reasonable discount (20%, not unrealistic)
    - No suspicious links mentioned

    Balance: While promotional, this appears to be legitimate
    marketing from a company the user has a relationship with.
  </thinking>
  <output>not-spam (promotional)</output>
</example>
```

---

## Domain-Specific Generation

### Code Analysis

```text
Input categories:
1. Clean, well-structured code
2. Code with obvious bugs
3. Code with subtle issues
4. Performance concerns
5. Security vulnerabilities
```

### Document Summarization

```text
Input categories:
1. Short, focused documents
2. Long, multi-topic documents
3. Technical documents
4. Narrative documents
5. Documents with conflicting information
```

### Customer Support

```text
Input categories:
1. Simple, direct questions
2. Complex, multi-part requests
3. Complaints/negative sentiment
4. Ambiguous requests
5. Off-topic or inappropriate messages
```

---

## Using Claude to Generate Test Cases

You can use Claude to help generate test cases:

**Prompt pattern:**

```text
I'm creating examples for a prompt that [task description].

Generate 5 diverse test inputs that cover:
1. Typical cases
2. Edge cases
3. Challenging scenarios

For each input, provide:
- The input text
- The expected output
- Brief reasoning for why this is the correct output
```

**Important:** Always review and refine generated test cases. Claude may miss domain-specific nuances or generate unrealistic examples.

---

## Quality Checklist for Generated Examples

Before using generated examples in your prompt:

- [ ] Each example is realistic for the use case
- [ ] Examples cover diverse scenarios
- [ ] Edge cases are represented
- [ ] Reasoning is clear and consistent
- [ ] Output format is identical across examples
- [ ] No contradictions between examples
- [ ] Examples align with task constraints

---

## Common Pitfalls

### Too Similar

**Problem:** All examples are variations of the same scenario.

**Fix:** Explicitly categorize input types and ensure each is represented.

### Too Easy

**Problem:** Examples only show obvious cases.

**Fix:** Include at least one ambiguous or challenging case that requires nuanced reasoning.

### Inconsistent Format

**Problem:** Output format varies between examples.

**Fix:** Standardize format across all examples; use the same structure.

### Missing Reasoning

**Problem:** Examples show input/output but not thinking process.

**Fix:** Add `<thinking>` sections that demonstrate the expected analysis.

### Unrealistic Inputs

**Problem:** Generated inputs don't match real-world usage.

**Fix:** Base inputs on actual data when possible; validate with domain experts.

---

## Next Steps

After generating test cases:

1. **Integrate into prompt** - See [example-enrichment-patterns.md](../patterns/example-enrichment-patterns.md)
2. **Test the improved prompt** - Run against additional inputs
3. **Iterate if needed** - See [iterative-refinement.md](iterative-refinement.md)
