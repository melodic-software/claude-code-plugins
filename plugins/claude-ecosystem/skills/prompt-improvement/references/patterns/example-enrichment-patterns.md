# Example Enrichment Patterns

This reference provides patterns for transforming basic examples into enhanced examples that demonstrate reasoning.

## Why Enrich Examples?

Enhanced examples teach Claude:

1. **HOW to reason:** Not just what to output, but the thinking process
2. **Intermediate steps:** What analysis happens between input and output
3. **Decision criteria:** Why one answer over another
4. **Format expectations:** Exact structure to follow

**Query docs-management for official guidance:**

```text
Find documentation about multishot prompting and example formatting
```

---

## Basic Enrichment Pattern

### Before (Basic)

```xml
<example>
  <input>Is 17 prime?</input>
  <output>Yes</output>
</example>
```

### After (Enriched)

```xml
<example>
  <input>Is 17 prime?</input>
  <thinking>
    To determine if 17 is prime, I check for divisors other than 1 and 17.
    - 17 / 2 = 8.5 (not divisible)
    - 17 / 3 = 5.67 (not divisible)
    - 17 / 4 = 4.25 (not divisible)
    sqrt(17) ≈ 4.1, so I only need to check up to 4.
    No divisors found.
  </thinking>
  <output>Yes, 17 is prime.</output>
</example>
```

---

## Enrichment Pattern Types

### Pattern 1: Analysis Steps

Show the step-by-step breakdown:

```xml
<example>
  <input>
    Customer email: "Your product broke after 2 days. This is unacceptable. I want a refund immediately."
  </input>
  <thinking>
    Step 1: Identify the issue
    - Product malfunction (broke after 2 days)

    Step 2: Assess sentiment
    - Strongly negative ("unacceptable", demanding language)
    - Urgency present ("immediately")

    Step 3: Determine priority
    - Product failure = actionable
    - Strong sentiment = needs careful handling
    - Priority: HIGH

    Step 4: Determine action
    - Refund request is clear
    - Needs empathetic response + refund process
  </thinking>
  <output>
    Priority: HIGH
    Category: Refund Request
    Sentiment: Negative
    Action: Process refund, send apology email
  </output>
</example>
```

### Pattern 2: Criteria Evaluation

Show how each criterion is evaluated:

```xml
<example>
  <input>
    Job application for Senior Developer role:
    - 3 years experience
    - Python, JavaScript skills
    - No team lead experience
    - Strong portfolio
  </input>
  <thinking>
    Evaluating against criteria:

    [x] Technical skills: Python, JavaScript - MEETS (2/2 required)
    [x] Portfolio: Strong - MEETS
    [ ] Experience: 3 years - BELOW (5 required for Senior)
    [ ] Leadership: None - BELOW (team lead preferred)

    Score: 2/4 criteria met
    Key gap: Experience level insufficient for Senior role
  </thinking>
  <output>
    Decision: REJECT for Senior role
    Alternative: Consider for Mid-level Developer position
    Reasoning: Technical skills strong but experience insufficient
  </output>
</example>
```

### Pattern 3: Evidence Gathering

Show quote extraction and evidence chain:

```xml
<example>
  <input>
    Document: "The Q3 results show a 15% increase in revenue compared to Q2. However, customer acquisition costs rose by 22%, offsetting some gains. Net profit margin declined slightly to 8.2%."

    Question: Was Q3 profitable?
  </input>
  <thinking>
    Extracting relevant evidence:

    1. "15% increase in revenue" - Positive indicator
    2. "customer acquisition costs rose by 22%" - Negative indicator
    3. "Net profit margin declined slightly to 8.2%" - Key metric

    Analysis:
    - Profit margin of 8.2% means yes, it was profitable
    - "Declined slightly" indicates less profitable than before
    - But still positive margin = still profitable
  </thinking>
  <output>
    Yes, Q3 was profitable with an 8.2% net profit margin, though this represents a slight decline from the previous quarter due to increased customer acquisition costs.

    Evidence: "Net profit margin declined slightly to 8.2%"
  </output>
</example>
```

### Pattern 4: Comparison/Weighing

Show how competing factors are balanced:

```xml
<example>
  <input>
    Option A: Cloud hosting - $500/month, 99.9% uptime, 24/7 support
    Option B: On-premise - $300/month, 99.5% uptime, business hours support

    Priority: Reliability > Cost
  </input>
  <thinking>
    Comparing on each factor:

    Cost:
    - A: $500/month
    - B: $300/month
    - Winner: B (saves $200/month)

    Reliability:
    - A: 99.9% uptime = ~8.7 hours downtime/year
    - B: 99.5% uptime = ~43.8 hours downtime/year
    - Winner: A (5x better uptime)

    Support:
    - A: 24/7
    - B: Business hours only
    - Winner: A (critical for reliability)

    Applying priority (Reliability > Cost):
    - Reliability strongly favors A
    - $200/month savings doesn't offset 35+ hours additional downtime
  </thinking>
  <output>
    Recommendation: Option A (Cloud hosting)

    Rationale: Given the priority on reliability, the 99.9% uptime and 24/7 support justify the additional $200/month. The 35+ hours of additional annual downtime with Option B would likely cost more in lost productivity than the savings.
  </output>
</example>
```

### Pattern 5: Error Handling

Show how to handle edge cases or invalid inputs:

```xml
<example>
  <input>
    Extract email from: "Contact us at our office during business hours"
  </input>
  <thinking>
    Scanning text for email patterns:
    - Looking for pattern: [text]@[domain].[tld]
    - No @ symbol found
    - No email pattern detected

    Fallback check:
    - "Contact us" - suggests contact information expected
    - "office" - location reference, not email
    - "business hours" - time reference

    Conclusion: No email present in text
  </thinking>
  <output>
    Email: NOT FOUND

    Note: The text mentions contact information but no email address is provided.
  </output>
</example>
```

---

## Enrichment by Task Type

### Classification Tasks

Show the indicators that led to classification:

```xml
<thinking>
  Classification indicators for [CATEGORY]:
  + [Indicator 1 present]
  + [Indicator 2 present]
  - [Counter-indicator absent]

  Confidence: HIGH/MEDIUM/LOW
</thinking>
```

### Extraction Tasks

Show the search and validation process:

```xml
<thinking>
  Searching for [FIELD]:
  - Location found: [where in document]
  - Raw value: [extracted text]
  - Validation: [checks performed]
  - Normalized value: [final value]
</thinking>
```

### Generation Tasks

Show the planning before generation:

```xml
<thinking>
  Planning response:
  - Key points to cover: [list]
  - Tone: [specification]
  - Length target: [specification]
  - Structure: [outline]
</thinking>
```

### Analysis Tasks

Show the framework applied:

```xml
<thinking>
  Applying [FRAMEWORK] analysis:

  [Dimension 1]:
  - Observation: [what I see]
  - Implication: [what it means]

  [Dimension 2]:
  - Observation: [what I see]
  - Implication: [what it means]

  Synthesis: [combined conclusion]
</thinking>
```

---

## Enrichment Depth Guidelines

### Light Enrichment (1-2 sentences)

For simple tasks:

```xml
<thinking>
  The text contains "love" and "amazing" - clear positive sentiment.
</thinking>
```

### Standard Enrichment (3-5 steps)

For moderate tasks:

```xml
<thinking>
  1. Identified key terms: [terms]
  2. Checked against criteria: [evaluation]
  3. Considered edge cases: [consideration]
  4. Reached conclusion: [reasoning]
</thinking>
```

### Deep Enrichment (Full analysis)

For complex tasks:

```xml
<thinking>
  [Multi-paragraph analysis with sections, sub-points, and explicit reasoning chains]
</thinking>
```

Match enrichment depth to task complexity.

---

## Multiple Examples Strategy

When including multiple examples, diversify what they demonstrate:

### Example 1: Typical Case

Shows standard processing:

```xml
<example>
  <input>[Typical, straightforward input]</input>
  <thinking>[Standard analysis process]</thinking>
  <output>[Expected output]</output>
</example>
```

### Example 2: Edge Case

Shows handling of boundary conditions:

```xml
<example>
  <input>[Edge case or boundary input]</input>
  <thinking>[How to identify and handle edge case]</thinking>
  <output>[Appropriate edge case output]</output>
</example>
```

### Example 3: Challenging Case

Shows nuanced reasoning:

```xml
<example>
  <input>[Ambiguous or complex input]</input>
  <thinking>[Extended reasoning with considerations of alternatives]</thinking>
  <output>[Justified output with caveats if needed]</output>
</example>
```

---

## Common Enrichment Mistakes

### Mistake 1: Thinking doesn't match output

**Bad:**

```xml
<thinking>
  The sentiment is clearly positive.
</thinking>
<output>negative</output>
```

**Fix:** Ensure thinking logically leads to output.

### Mistake 2: Thinking is too generic

**Bad:**

```xml
<thinking>
  I will analyze the text and determine the answer.
</thinking>
```

**Fix:** Show specific analysis, not meta-description.

### Mistake 3: Output format doesn't match

**Bad:**

Example shows JSON, but real examples show prose.

**Fix:** All examples must use identical output structure.

### Mistake 4: Missing the why

**Bad:**

```xml
<thinking>
  The answer is 42.
</thinking>
```

**Fix:** Show the reasoning, not just the answer.

---

## Enrichment Checklist

Before finalizing enriched examples:

- [ ] Thinking shows actual reasoning process
- [ ] Thinking logically leads to output
- [ ] All examples use consistent format
- [ ] Edge cases are represented
- [ ] Depth matches task complexity
- [ ] No contradictions between examples
- [ ] Examples cover diverse scenarios

---

## Next Steps

- For test case generation, see [../workflows/test-case-generation.md](../workflows/test-case-generation.md)
- For chain of thought patterns, see [cot-patterns.md](cot-patterns.md)
- For basic transformations, see [../examples/basic-transformations.md](../examples/basic-transformations.md)
