# Debugging Guide

This reference provides a systematic approach to debugging prompt issues.

## The Debugging Framework

### Step 1: Identify the Problem Type

| Symptom | Problem Category | Section |
| --------- | ----------------- | --------- |
| Wrong answer/output | Content Issue | [Content Issues](#debugging-content-issues) |
| Wrong format | Format Issue | [Format Issues](#debugging-format-issues) |
| Inconsistent results | Stability Issue | [Stability Issues](#debugging-stability-issues) |
| Too slow/expensive | Efficiency Issue | [Efficiency Issues](#debugging-efficiency-issues) |
| Ignores instructions | Instruction Issue | [Instruction Issues](#debugging-instruction-issues) |

### Step 2: Isolate the Cause

For each problem type, follow the specific debugging flow.

### Step 3: Apply Targeted Fix

Implement the minimum change needed to address the issue.

### Step 4: Verify and Iterate

Test the fix with multiple inputs before considering it resolved.

---

## Debugging Content Issues

**Symptoms:** Wrong answers, incorrect analysis, missing information

### Diagnostic Questions

1. Is the task clearly defined?
2. Are the criteria explicit?
3. Do examples demonstrate correct reasoning?
4. Is necessary context provided?

### Debugging Flow

```text
START
  |
  v
Does the prompt clearly state what to do?
  |
  +-- NO --> Add explicit task definition
  |
  +-- YES
        |
        v
      Are success criteria defined?
        |
        +-- NO --> Add evaluation criteria
        |
        +-- YES
              |
              v
            Do examples show correct outputs?
              |
              +-- NO --> Add/fix examples
              |
              +-- YES
                    |
                    v
                  Is reasoning visible in examples?
                    |
                    +-- NO --> Enrich examples with thinking
                    |
                    +-- YES --> Check for conflicting instructions
```

### Common Fixes

**Unclear task:**

```xml
<!-- Before -->
<instructions>
Process this data.
</instructions>

<!-- After -->
<instructions>
Extract all email addresses from the text.
Return each email on a separate line.
If no emails found, return "No emails found."
</instructions>
```

**Missing criteria:**

```xml
<criteria>
A valid email must:
- Contain exactly one @ symbol
- Have at least one character before @
- Have a domain with at least one dot
</criteria>
```

---

## Debugging Format Issues

**Symptoms:** Wrong structure, inconsistent output format, parsing failures

### Diagnostic Questions

1. Is the output format specified?
2. Do examples match the format specification?
3. Is prefill used for strict formats?
4. Are format instructions visible (not buried)?

### Debugging Flow

```text
START
  |
  v
Is there a <formatting> section?
  |
  +-- NO --> Add explicit formatting section
  |
  +-- YES
        |
        v
      Is it placed at end of prompt?
        |
        +-- NO --> Move to end (last instructions matter most)
        |
        +-- YES
              |
              v
            Do examples show exact format?
              |
              +-- NO --> Update examples to match format
              |
              +-- YES
                    |
                    v
                  Is format critical (JSON/XML)?
                    |
                    +-- YES --> Add prefill
                    |
                    +-- NO --> Strengthen format language
```

### Common Fixes

**Missing format specification:**

```xml
<formatting>
Return your response as JSON with this structure:
{
  "classification": "positive" | "negative" | "neutral",
  "confidence": 0.0-1.0,
  "key_phrases": ["phrase1", "phrase2"]
}
</formatting>
```

**Format not followed - add prefill:**

```text
Prefill: {
```

**Examples don't match format:**

Ensure every example uses the exact expected structure.

---

## Debugging Stability Issues

**Symptoms:** Different results for same input, unpredictable quality

### Diagnostic Questions

1. Are instructions specific or vague?
2. Are edge cases handled?
3. Is there a decision framework?
4. Are examples diverse enough?

### Debugging Flow

```text
START
  |
  v
Run prompt 5 times with same input
  |
  v
Are results consistent?
  |
  +-- YES --> Problem may be input variation
  |
  +-- NO
        |
        v
      Which part varies?
        |
        +-- FORMAT --> See Format Issues
        |
        +-- CONTENT
              |
              v
            Are decision criteria explicit?
              |
              +-- NO --> Add explicit decision rules
              |
              +-- YES
                    |
                    v
                  Are there ambiguous cases?
                    |
                    +-- YES --> Add examples for ambiguous cases
                    |
                    +-- NO --> Add "when in doubt" guidance
```

### Common Fixes

**Vague instructions:**

```xml
<!-- Before -->
<instructions>
Categorize the feedback.
</instructions>

<!-- After -->
<instructions>
Categorize feedback using ONLY these categories:
- bug: Product malfunction or error
- feature: Request for new functionality
- complaint: Negative sentiment without specific issue
- praise: Positive feedback
- question: Asking for information

If feedback fits multiple categories, use the primary one.
When uncertain, prefer the more specific category.
</instructions>
```

**Decision framework:**

```xml
<decision_rules>
Priority order for ambiguous cases:
1. If safety-related, always flag as HIGH priority
2. If revenue-impacting, prefer MEDIUM over LOW
3. When genuinely unclear, state uncertainty in output
</decision_rules>
```

---

## Debugging Efficiency Issues

**Symptoms:** Slow response time, high token usage, expensive to run

### Diagnostic Questions

1. Is CoT level appropriate for task complexity?
2. Are there unnecessary instructions?
3. Are examples too verbose?
4. Is the prompt repeating itself?

### Debugging Flow

```text
START
  |
  v
Is this a simple task?
  |
  +-- YES --> Is structured CoT used?
  |             |
  |             +-- YES --> Reduce or remove CoT
  |             |
  |             +-- NO --> Check example count
  |
  +-- NO
        |
        v
      Count tokens in prompt
        |
        v
      > 1000 tokens?
        |
        +-- YES --> Look for redundancy
        |           - Duplicate instructions
        |           - Verbose examples
        |           - Unnecessary context
        |
        +-- NO --> Check output verbosity
                   - Add length constraints
                   - Reduce thinking depth
```

### Common Fixes

**Over-engineered simple task:**

```xml
<!-- Before: 800 tokens for simple classification -->
<instructions>
You are an expert sentiment analyst with deep understanding...
[Long preamble]
</instructions>
<examples>
[5 verbose examples]
</examples>

<!-- After: 150 tokens -->
<instructions>
Classify as positive, negative, or neutral.
</instructions>
<examples>
  <example>
    <input>Love it!</input>
    <output>positive</output>
  </example>
  <example>
    <input>Terrible.</input>
    <output>negative</output>
  </example>
</examples>
```

**Verbose thinking:**

```xml
<instructions>
Keep analysis concise (3-5 bullet points max in thinking section).
Focus only on decisive factors.
</instructions>
```

---

## Debugging Instruction Issues

**Symptoms:** Claude ignores specific instructions, does unexpected things

### Diagnostic Questions

1. Are instructions buried in text?
2. Do instructions conflict with each other?
3. Are instructions at odds with examples?
4. Is the instruction specific enough?

### Debugging Flow

```text
START
  |
  v
Is the ignored instruction visible?
  |
  +-- NO --> Move to dedicated section (start or end)
  |
  +-- YES
        |
        v
      Is it specific and actionable?
        |
        +-- NO --> Rewrite to be concrete
        |
        +-- YES
              |
              v
            Does it conflict with other instructions?
              |
              +-- YES --> Resolve conflict, remove one
              |
              +-- NO
                    |
                    v
                  Do examples violate the instruction?
                    |
                    +-- YES --> Fix examples
                    |
                    +-- NO --> Strengthen with "MUST" or "ALWAYS"
```

### Common Fixes

**Buried instruction:**

```xml
<!-- Before: Instruction lost in paragraph -->
<instructions>
You are a helpful assistant. Please be concise. When analyzing documents, consider the context and provide insights. Always cite your sources. Focus on key points and avoid unnecessary detail...
</instructions>

<!-- After: Clear sections -->
<instructions>
You are a document analyst.

TASK:
Analyze the document and identify key insights.

REQUIREMENTS:
- Always cite sources with page numbers
- Keep analysis concise (under 200 words)
- Focus on actionable insights
</instructions>
```

**Vague instruction:**

```xml
<!-- Before -->
Be concise.

<!-- After -->
Keep your response under 100 words total.
```

**Conflicting instructions:**

```xml
<!-- Before: Conflict -->
Be thorough and comprehensive.
Keep responses short.

<!-- After: Resolved -->
Provide comprehensive analysis in bullet point format.
Cover all key points; elaborate only where necessary.
```

---

## The Elimination Method

When the issue is unclear, systematically eliminate components:

### Process

1. **Start with minimal prompt:** Task definition only
2. **Test:** Does it work?
3. **Add one component:** Instructions, examples, formatting
4. **Test again:** Still working?
5. **Continue adding:** One component at a time
6. **Identify breakpoint:** Which addition caused the issue?

### Example

```text
Version 1: Basic task (works)
Version 2: + Instructions (works)
Version 3: + Examples (broken!)
--> Problem is in examples
--> Debug examples specifically
```

---

## Debugging Checklist

When stuck, run through this checklist:

### Prompt Structure

- [ ] Is there a clear task definition?
- [ ] Are instructions in a dedicated section?
- [ ] Is formatting explicitly specified?
- [ ] Are examples present and correct?

### Instructions Quality

- [ ] Are all instructions specific and actionable?
- [ ] No contradictions between instructions?
- [ ] Edge cases addressed?
- [ ] Decision criteria explicit?

### Example Quality

- [ ] Do examples match format specification?
- [ ] Is reasoning shown in examples?
- [ ] Are examples diverse (typical + edge cases)?
- [ ] No conflicts between examples?

### Common Fixes to Try

- [ ] Add/move formatting section to end
- [ ] Use prefill for format compliance
- [ ] Reduce CoT level for simple tasks
- [ ] Add explicit handling for missing data
- [ ] Strengthen language (MUST, ALWAYS, ONLY)

---

## Next Steps

- For common issues, see [common-issues.md](common-issues.md)
- For trade-off decisions, see [tradeoffs-guide.md](tradeoffs-guide.md)
- For iterative improvement, see [../workflows/iterative-refinement.md](../workflows/iterative-refinement.md)
