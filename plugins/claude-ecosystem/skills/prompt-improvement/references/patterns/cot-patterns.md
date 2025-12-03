# Chain of Thought Patterns

This reference provides patterns for adding chain of thought (CoT) reasoning to prompts.

## Why Chain of Thought?

Chain of thought prompting improves accuracy on complex tasks by:

1. **Making reasoning visible:** Claude shows its work
2. **Reducing errors:** Step-by-step analysis catches mistakes
3. **Enabling verification:** You can check the reasoning, not just the answer
4. **Improving consistency:** Structured thinking produces consistent results

**Query docs-management for official guidance:**

```text
Find documentation about chain of thought prompting and step-by-step reasoning
```

---

## CoT Level Selection

| Task Complexity | Recommended CoT Level | Example Tasks |
|----------------|----------------------|---------------|
| Simple | None or Basic | Factual lookups, simple classification |
| Moderate | Basic | Standard classification, formatting |
| Complex | Guided | Analysis, comparison, multi-step |
| Very Complex | Structured | Research, strategic decisions, debugging |

---

## Level 1: Basic CoT

Simple instruction to think before answering.

### Pattern

```xml
<instructions>
[Task description]

Think step-by-step before providing your answer.
</instructions>
```

### Example

```xml
<instructions>
Determine whether the following math problem is solved correctly.

Think step-by-step through the calculation before concluding.
</instructions>

<problem>
15 x 7 = 115
</problem>

<formatting>
First show your step-by-step verification, then state whether the answer is correct or incorrect.
</formatting>
```

### When to Use

- Simple verification tasks
- When you want visible reasoning without structure
- Quick accuracy boost for moderate tasks

---

## Level 2: Guided CoT

Specific steps for Claude to follow.

### Pattern

```xml
<instructions>
[Task description]

Before answering, work through these steps:
1. [First analysis step]
2. [Second analysis step]
3. [Third analysis step]
4. [Final step leading to answer]
</instructions>
```

### Example

```xml
<instructions>
Analyze this customer review to determine overall sentiment.

Before classifying, work through these steps:
1. Identify explicitly positive statements
2. Identify explicitly negative statements
3. Note any mixed or ambiguous language
4. Weigh the balance and determine overall sentiment
</instructions>

<review>
{{review_text}}
</review>

<formatting>
Show your analysis for each step, then provide your classification: positive, negative, or mixed.
</formatting>
```

### When to Use

- Tasks with known analysis methodology
- When specific considerations must be addressed
- Multi-factor evaluation tasks

---

## Level 3: Structured CoT

XML-tagged thinking with clear separation between reasoning and output.

### Pattern

```xml
<instructions>
[Task description]

Analyze the problem in <thinking> tags. Include:
- [Specific analysis element 1]
- [Specific analysis element 2]
- [Specific analysis element 3]

Then provide your final answer in <answer> tags.
</instructions>
```

### Example

```xml
<instructions>
You are a medical triage assistant. Assess the patient symptoms and recommend a course of action.

Analyze in <thinking> tags. Include:
- Symptom identification and severity
- Potential conditions to consider
- Red flags or emergency indicators
- Risk assessment

Then provide your recommendation in <answer> tags.
</instructions>

<symptoms>
{{patient_symptoms}}
</symptoms>

<formatting>
<thinking>
[Your detailed analysis here]
</thinking>
<answer>
[Your recommendation here]
</answer>
</formatting>
```

### When to Use

- High-stakes decisions requiring justification
- Complex analysis with multiple factors
- When reasoning must be reviewable/auditable

---

## Level 4: Multi-Stage CoT

Multiple distinct thinking stages for very complex tasks.

### Pattern

```xml
<instructions>
[Task description]

Complete your analysis in stages:

<stage1_understanding>
[Initial comprehension and problem framing]
</stage1_understanding>

<stage2_analysis>
[Deep analysis of components]
</stage2_analysis>

<stage3_synthesis>
[Combining insights and forming conclusions]
</stage3_synthesis>

<answer>
[Final output]
</answer>
</instructions>
```

### Example

```xml
<instructions>
Evaluate whether the proposed business strategy is viable.

Complete your analysis in stages:

<understanding>
First, summarize the key elements of the proposed strategy.
What is being proposed? What are the stated goals?
</understanding>

<market_analysis>
Analyze the market conditions and competitive landscape.
Is the market opportunity real? What are the threats?
</market_analysis>

<capability_assessment>
Assess whether the company has the capabilities to execute.
What resources are needed? What gaps exist?
</capability_assessment>

<risk_evaluation>
Identify key risks and potential failure modes.
What could go wrong? How severe would failures be?
</risk_evaluation>

<synthesis>
Combine your analysis into a coherent assessment.
</synthesis>

<recommendation>
Provide your final recommendation with key conditions or caveats.
</recommendation>
</instructions>
```

### When to Use

- Strategic or executive-level analysis
- Multi-disciplinary evaluation
- Very complex decisions with many factors

---

## CoT for Specific Domains

### Code Analysis CoT

```xml
<instructions>
Review this code for bugs and issues.

In <thinking> tags, analyze:
1. Logic flow and edge cases
2. Error handling completeness
3. Security considerations
4. Performance implications

Then provide findings in <output> tags.
</instructions>
```

### Mathematical Reasoning CoT

```xml
<instructions>
Solve this problem showing your work.

In <working> tags:
1. Identify given information
2. State the approach/formula
3. Show each calculation step
4. Verify the result

Provide final answer in <answer> tags.
</instructions>
```

### Document Analysis CoT

```xml
<instructions>
Analyze this document and extract key insights.

In <analysis> tags:
1. Identify main themes
2. Note supporting evidence for each theme
3. Identify any gaps or contradictions
4. Consider implications

Provide summary in <summary> tags.
</instructions>
```

---

## CoT in Examples

When using structured CoT, examples must demonstrate the thinking process:

### Before (Bad)

```xml
<example>
  <input>Is 17 a prime number?</input>
  <output>Yes, 17 is prime.</output>
</example>
```

### After (Good)

```xml
<example>
  <input>Is 17 a prime number?</input>
  <thinking>
    To determine if 17 is prime, I need to check if it has any divisors other than 1 and itself.

    Checking divisibility:
    - 17 / 2 = 8.5 (not divisible)
    - 17 / 3 = 5.67 (not divisible)
    - 17 / 4 = 4.25 (not divisible)

    I only need to check up to sqrt(17) ≈ 4.1, so I'm done.

    No divisors found other than 1 and 17.
  </thinking>
  <output>Yes, 17 is prime because it has no divisors other than 1 and itself.</output>
</example>
```

---

## Conditional CoT

Sometimes you want different CoT depths based on input:

```xml
<instructions>
Classify this support ticket by priority.

For straightforward tickets:
- Briefly note the issue type and assign priority

For complex or ambiguous tickets:
- First identify all issues mentioned
- Assess severity of each
- Consider combined impact
- Then assign priority with justification

Use <thinking> tags for your analysis, <priority> tags for the final assignment.
</instructions>
```

---

## CoT Verbosity Control

### Concise CoT

When you want reasoning but brief output:

```xml
<instructions>
[Task]

Think through this step-by-step, but keep your reasoning concise.
Focus only on the key decision points.
</instructions>
```

### Exhaustive CoT

When thorough documentation matters:

```xml
<instructions>
[Task]

Document your complete reasoning process. Include:
- All assumptions you're making
- Alternatives you considered and why you rejected them
- Confidence level for each conclusion
- Any uncertainties or caveats
</instructions>
```

---

## Common Mistakes

### Mistake 1: CoT for Simple Tasks

**Problem:** Adding complex CoT to trivial tasks

```xml
<!-- Overkill for this task -->
<instructions>
What is the capital of France?

Think through the following stages:
<geography_context>...</geography_context>
<historical_analysis>...</historical_analysis>
<current_political_status>...</current_political_status>
<answer>...</answer>
</instructions>
```

**Fix:** Simple tasks don't need structured CoT

```xml
<instructions>
What is the capital of France?
</instructions>
```

### Mistake 2: Thinking Tags Without Guidance

**Problem:** Asking for thinking without specifying what to think about

```xml
<instructions>
Analyze this data and provide insights.
Use <thinking> tags.
</instructions>
```

**Fix:** Specify what the thinking should include

```xml
<instructions>
Analyze this data and provide insights.

In <thinking> tags, include:
- Key patterns observed
- Anomalies or outliers
- Potential causes for trends
- Confidence in your observations
</instructions>
```

### Mistake 3: Examples Without Matching CoT

**Problem:** Structured CoT in instructions but simple examples

```xml
<instructions>
Use <thinking> and <answer> tags.
</instructions>

<example>
  <input>...</input>
  <output>Just the answer without thinking</output>
</example>
```

**Fix:** Examples must match the expected structure

```xml
<example>
  <input>...</input>
  <thinking>Reasoning shown here</thinking>
  <answer>The answer</answer>
</example>
```

---

## Next Steps

- For prefill patterns, see [prefill-patterns.md](prefill-patterns.md)
- For example enrichment, see [example-enrichment-patterns.md](example-enrichment-patterns.md)
- For XML tag library, see [xml-tagging-patterns.md](xml-tagging-patterns.md)
