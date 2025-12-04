# Prefill Patterns

This reference provides patterns for using the prefill technique to control Claude's output format and behavior.

## What is Prefilling?

Prefilling means pre-populating the start of Claude's response. By providing the beginning of the Assistant message, you can:

1. **Force format compliance:** Start with the expected format structure
2. **Skip preambles:** Avoid "Sure, I'd be happy to help..." openings
3. **Maintain character:** Keep persona consistent
4. **Guide structure:** Ensure output follows specific patterns

**Query docs-management for official guidance:**

```text
Find documentation about prefilling Claude's response for output control
```

---

## Basic Prefill Pattern

### Without Prefill

```text
User: Write a haiku about cats.
Assistant: Sure! Here's a haiku about cats for you:

Soft paws on the floor
Whiskers twitch in morning light
Silent hunter waits
```

### With Prefill

```text
User: Write a haiku about cats. Put it in <haiku> tags.
Assistant: <haiku>
```

Claude continues:

```text
<haiku>
Soft paws on the floor
Whiskers twitch in morning light
Silent hunter waits
</haiku>
```

The prefill (`<haiku>`) forces Claude to immediately output in the correct format.

---

## Pattern 1: JSON Output Enforcement

Force valid JSON output by starting with the opening brace:

### Prompt

```xml
<instructions>
Extract the person's name and email from the text.
Return valid JSON with "name" and "email" fields.
</instructions>

<text>
Contact John Smith at john.smith@example.com for more info.
</text>
```

### Prefill

```text
{
```

### Result

Claude continues:

```json
{
  "name": "John Smith",
  "email": "john.smith@example.com"
}
```

---

## Pattern 2: XML Tag Enforcement

Force structured output with opening tags:

### Prompt

```xml
<instructions>
Analyze the sentiment and provide your response with thinking and answer tags.
</instructions>

<text>
I love this product but the shipping was terrible.
</text>
```

### Prefill

```text
<thinking>
```

### Result

Claude continues:

```xml
<thinking>
Analyzing the sentiment of the text:
- Positive: "I love this product" - strong positive sentiment about the product itself
- Negative: "shipping was terrible" - strong negative sentiment about shipping
- Overall: Mixed sentiment, with product satisfaction offset by service dissatisfaction
</thinking>
<answer>
Mixed sentiment: Positive about product, negative about shipping.
</answer>
```

---

## Pattern 3: Skip Preamble

Prevent conversational openings:

### Without Prefill

```text
User: List 3 benefits of exercise.
Assistant: I'd be happy to help! Here are 3 key benefits of exercise:

1. Improved cardiovascular health
2. Better mental well-being
3. Increased energy levels
```

### With Prefill

```text
User: List 3 benefits of exercise.
Assistant: 1.
```

### Result

```text
1. Improved cardiovascular health
2. Better mental well-being
3. Increased energy levels
```

Direct output without preamble.

---

## Pattern 4: Maintain Character/Persona

Keep Claude in character when role-playing:

### Prompt

```xml
<instructions>
You are a pirate named Captain Jack. Always speak in pirate dialect.
</instructions>

User: How's the weather?
```

### Prefill

```text
Arr,
```

### Result

```text
Arr, the weather be fair today, me hearty! Clear skies and calm seas - perfect for sailin' to find treasure!
```

The "Arr," prefill reinforces the pirate persona.

---

## Pattern 5: Structured Analysis

Force multi-section output:

### Prompt

```xml
<instructions>
Analyze this code for security issues.
Structure your response with FINDINGS, SEVERITY, and RECOMMENDATIONS sections.
</instructions>

<code>
{{code}}
</code>
```

### Prefill

```text
## FINDINGS

1.
```

### Result

```text
## FINDINGS

1. SQL injection vulnerability on line 15
2. Unvalidated user input on line 23
3. Hardcoded credentials on line 7

## SEVERITY

- Finding 1: CRITICAL
- Finding 2: HIGH
- Finding 3: CRITICAL

## RECOMMENDATIONS

1. Use parameterized queries
2. Implement input validation
3. Move credentials to environment variables
```

---

## Pattern 6: Language Enforcement

Ensure output in specific language:

### Prompt

```xml
<instructions>
Translate the following to Spanish.
</instructions>

<text>
Hello, how are you today?
</text>
```

### Prefill

```text
Hola,
```

### Result

```text
Hola, como estas hoy?
```

Prefilling with target language ensures immediate compliance.

---

## Pattern 7: Code Output

Force code-only output:

### Prompt

```xml
<instructions>
Write a Python function that calculates factorial.
Return only the code, no explanation.
</instructions>
```

### Prefill

```python
def factorial(n):
```

### Result

```python
def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)
```

---

## Pattern 8: Table Output

Force tabular format:

### Prompt

```xml
<instructions>
List the top 3 programming languages with their primary use cases.
Format as a markdown table.
</instructions>
```

### Prefill

```text
| Language | Primary Use Case |
|----------|-----------------|
|
```

### Result

```text
| Language | Primary Use Case |
|----------|-----------------|
| Python | Data science, automation, web backends |
| JavaScript | Web development, frontend, Node.js backends |
| Java | Enterprise applications, Android development |
```

---

## Combining Prefill with XML Structure

For complex prompts, prefill complements XML structure:

### Full Pattern

```xml
<instructions>
Analyze the document and extract key points.
Provide your thinking process, then the extracted points.
</instructions>

<document>
{{document}}
</document>

<formatting>
Use <thinking> tags for analysis, <key_points> tags for extraction.
</formatting>
```

### Prefill

```text
<thinking>
Let me analyze the document systematically.

First,
```

### Result

The prefill guides Claude into immediate structured analysis mode.

---

## When to Use Prefill

### Use Prefill When

- Format compliance is critical (JSON, XML, specific structure)
- Preambles waste tokens or confuse downstream processing
- Character/persona consistency matters
- You need reliable parsing of output

### Don't Use Prefill When

- Output format is flexible
- Natural conversational tone is preferred
- The task doesn't have strict output requirements

---

## Prefill Best Practices

### 1. Match the Expected Format

**Good:** Prefill mirrors the instruction's format

```text
Instructions: Return JSON with "result" field
Prefill: {"result":
```

**Bad:** Prefill doesn't match

```text
Instructions: Return JSON
Prefill: Here is the result:
```

### 2. Don't Over-Constrain

**Good:** Open enough for Claude to complete naturally

```text
Prefill: {
```

**Bad:** Too specific, may conflict with content

```text
Prefill: {"name": "John",
```

### 3. Use Consistent Style

If your prompt uses specific tag names, prefill with those tags.

### 4. Test Edge Cases

Prefill may interact unexpectedly with certain inputs. Test your prompts with diverse examples.

---

## Common Prefill Snippets

| Purpose | Prefill |
| --------- | --------- |
| JSON object | `{` |
| JSON array | `[` |
| XML thinking | `<thinking>` |
| Numbered list | `1.` |
| Markdown heading | `##` |
| Code block | `\`\`\`python` |
| Table | `\| Header \|` |
| Direct answer | First word of expected answer |

---

## Platform Notes

Prefill behavior may vary by platform:

- **API:** Prefill via `assistant` message in conversation
- **Claude Code:** Use in slash commands or agent instructions
- **Console/Workbench:** Prefill supported in playground

**Query docs-management for platform-specific guidance:**

```text
Find documentation about API message structure and prefilling
```

---

## Next Steps

- For XML patterns, see [xml-tagging-patterns.md](xml-tagging-patterns.md)
- For chain of thought patterns, see [cot-patterns.md](cot-patterns.md)
- For example enrichment, see [example-enrichment-patterns.md](example-enrichment-patterns.md)
