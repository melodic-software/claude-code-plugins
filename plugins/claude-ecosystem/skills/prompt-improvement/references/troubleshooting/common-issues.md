# Common Issues and Fixes

This reference provides solutions for common problems encountered during prompt improvement.

## Issue 1: Output Format Not Followed

### Symptoms

- Claude ignores formatting instructions
- Output structure varies between runs
- JSON/XML format is inconsistent

### Causes

1. Formatting instructions buried in long prompt
2. No examples demonstrating the format
3. Conflicting format instructions

### Fixes

**Move formatting to prominent position:**

```xml
<formatting>
[Put formatting instructions in dedicated section at end]
</formatting>
```

**Add examples that demonstrate exact format:**

```xml
<example>
  <output>
    {
      "field1": "value",
      "field2": "value"
    }
  </output>
</example>
```

**Use prefill to enforce format:**

```text
Prefill: {
```

**Query docs-management:**

```text
Find documentation about prefilling Claude's response for output control
```

---

## Issue 2: Chain of Thought Too Verbose

### Symptoms

- Thinking sections are excessively long
- Analysis includes unnecessary detail
- Response time is slow due to verbose reasoning

### Causes

1. No length constraints on thinking
2. CoT level too high for task complexity
3. Examples show verbose reasoning

### Fixes

**Add conciseness instruction:**

```xml
<instructions>
In <thinking> tags, provide concise analysis. Focus on key decision points only.
Keep thinking to 3-5 bullet points maximum.
</instructions>
```

**Reduce CoT level:**

- Change from Structured to Guided
- Change from Guided to Basic
- Remove CoT for simple tasks

**Show concise examples:**

```xml
<thinking>
- Key observation 1
- Key observation 2
- Conclusion: X
</thinking>
```

---

## Issue 3: Examples Not Influencing Output

### Symptoms

- Claude ignores example format
- Reasoning doesn't match example style
- Output contradicts example patterns

### Causes

1. Too few examples (1 may not establish pattern)
2. Examples conflict with instructions
3. Examples not diverse enough
4. Examples placed in wrong location

### Fixes

**Use 2-3 diverse examples minimum:**

```xml
<examples>
  <example>[Typical case]</example>
  <example>[Edge case]</example>
  <example>[Challenging case]</example>
</examples>
```

**Ensure examples match instructions exactly:**

If instructions say "output JSON," examples must show JSON.

**Place examples before variable input:**

```xml
<instructions>...</instructions>
<examples>...</examples>
<input>{{variable}}</input>
```

---

## Issue 4: Inconsistent Results

### Symptoms

- Same input produces different outputs
- Quality varies between runs
- Format compliance is unpredictable

### Causes

1. Instructions are ambiguous
2. Edge cases not covered
3. Missing constraints
4. Temperature too high (API setting)

### Fixes

**Make instructions explicit:**

```xml
<!-- Bad -->
<instructions>
Summarize the document briefly.
</instructions>

<!-- Good -->
<instructions>
Summarize the document in exactly 3 sentences.
Each sentence should cover: main point, key evidence, conclusion.
</instructions>
```

**Add constraint examples:**

Show what to do AND what NOT to do.

**Add explicit handling for edge cases:**

```xml
<rules>
If the document is empty, return: "No content to summarize."
If the document is less than 50 words, summarize in 1 sentence.
</rules>
```

---

## Issue 5: Missing Information Handling

### Symptoms

- Claude makes up information when data is missing
- No indication when information isn't available
- Confident answers for uncertain data

### Causes

1. No instruction on handling missing data
2. Examples don't show "not found" cases
3. No explicit "don't guess" instruction

### Fixes

**Add explicit missing data instructions:**

```xml
<instructions>
If information is not present in the document, state "Information not found" rather than guessing.
Never fabricate data. Only use what's explicitly stated.
</instructions>
```

**Include "not found" example:**

```xml
<example>
  <input>What is the CEO's age?</input>
  <thinking>
    Searching document for age information...
    No age mentioned for CEO.
  </thinking>
  <output>Information not found in document.</output>
</example>
```

---

## Issue 6: Reasoning and Output Mismatch

### Symptoms

- Thinking leads to one conclusion, output says another
- Inconsistency between analysis and final answer
- Contradictions within response

### Causes

1. Output not derived from thinking
2. Examples show mismatched thinking/output
3. Complex task causing reasoning drift

### Fixes

**Add explicit connection instruction:**

```xml
<instructions>
Your output must directly follow from your thinking.
In your final answer, reference the key conclusion from your analysis.
</instructions>
```

**Check example consistency:**

Verify all examples have thinking that logically leads to output.

**Add synthesis step:**

```xml
<thinking>
[Analysis]

Synthesis: Based on the above, the answer is X because [reason].
</thinking>
<output>X</output>
```

---

## Issue 7: Preambles Despite Instructions

### Symptoms

- Claude adds "Sure, I'd be happy to help!"
- Responses start with meta-commentary
- Instructions to skip preamble ignored

### Causes

1. Conversational mode overriding instructions
2. No prefill to force format
3. Instruction placement not optimal

### Fixes

**Use prefill:**

```text
Prefill: 1.  (for lists)
Prefill: {   (for JSON)
Prefill: <output>  (for XML)
```

**Strengthen instruction:**

```xml
<instructions>
Begin your response immediately with the requested content.
Do not include any preamble, introduction, or meta-commentary.
</instructions>
```

**Place format instruction last:**

The last instruction is often most followed.

---

## Issue 8: Over-Engineering Simple Tasks

### Symptoms

- Simple classification takes too long
- Unnecessary analysis for straightforward tasks
- Token usage much higher than expected

### Causes

1. CoT applied to tasks that don't need it
2. Too many examples for simple tasks
3. Verbose instructions for straightforward operations

### Fixes

**Match complexity to task:**

| Task Type | Recommended Approach |
| ----------- | --------------------- |
| Simple lookup | No CoT, minimal instructions |
| Basic classification | Basic CoT or examples only |
| Complex analysis | Full structured CoT |

**Simplify:**

```xml
<!-- Before: Over-engineered -->
<instructions>
You are an expert sentiment classifier with years of experience...
[500 words of instructions]
</instructions>

<!-- After: Appropriate -->
<instructions>
Classify as positive, negative, or neutral.
</instructions>
```

---

## Issue 9: Context Window Exceeded

### Symptoms

- Prompt is too long
- Examples get truncated
- Error about token limits

### Causes

1. Too many examples
2. Examples too verbose
3. Instructions repeated
4. Unnecessary context included

### Fixes

**Reduce example count:**

3-5 examples usually sufficient.

**Condense examples:**

Focus on the essential demonstration.

**Remove redundant instructions:**

Say things once, clearly.

**Use progressive disclosure:**

Load additional context only when needed.

---

## Issue 10: Task Scope Creep

### Symptoms

- Claude answers more than asked
- Provides unsolicited advice
- Expands beyond task boundaries

### Causes

1. Task boundaries not defined
2. No explicit scope limitation
3. Helpful tendency causes expansion

### Fixes

**Define explicit boundaries:**

```xml
<instructions>
Your task is ONLY to classify the sentiment.
Do not provide explanations, recommendations, or additional commentary.
</instructions>
```

**Use format constraints:**

```xml
<formatting>
Output exactly one word: positive, negative, or neutral.
</formatting>
```

**Add negative examples:**

Show what NOT to do:

```xml
<example type="incorrect">
  <input>Great product!</input>
  <output>
    positive

    Additional thoughts: The customer seems very satisfied...
  </output>
  <note>Wrong - includes unnecessary commentary</note>
</example>
```

---

## Quick Diagnosis Checklist

When a prompt isn't working:

1. **Format issues?** -> Add prefill, strengthen formatting section
2. **Inconsistent results?** -> Make instructions more explicit
3. **Wrong reasoning?** -> Check example consistency
4. **Too verbose?** -> Reduce CoT level, add length constraints
5. **Missing data?** -> Add not-found handling
6. **Preambles?** -> Use prefill
7. **Scope creep?** -> Define explicit boundaries
8. **Too slow?** -> Simplify for task complexity

---

## Next Steps

- For systematic debugging, see [debugging-guide.md](debugging-guide.md)
- For trade-off decisions, see [tradeoffs-guide.md](tradeoffs-guide.md)
- For iterative improvement, see [../workflows/iterative-refinement.md](../workflows/iterative-refinement.md)
