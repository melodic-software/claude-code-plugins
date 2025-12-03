# XML Tagging Patterns

This reference provides common XML tagging patterns for structuring prompts. For the complete tag reference, see [../metadata/tag-reference.md](../metadata/tag-reference.md).

## Why Use XML Tags?

XML tags provide structure that helps Claude:

1. **Distinguish components:** Separate instructions from data from examples
2. **Follow format:** Output in specified tag structure
3. **Reference precisely:** "Using the data in `<document>` tags..."
4. **Parse reliably:** Consistent extraction of outputs

**Query docs-management for official guidance:**

```text
Find documentation about XML tags for structuring prompts
```

---

## Core Structural Pattern

The fundamental pattern for improved prompts:

```xml
<instructions>
[Task definition and behavioral guidelines]
</instructions>

<context>
[Background information - optional if self-explanatory]
</context>

<examples>
[Demonstration cases with reasoning]
</examples>

[Variable input section]

<formatting>
[Output format specification]
</formatting>
```

---

## Pattern 1: Simple Task

For straightforward tasks with minimal context:

```xml
<instructions>
Classify the following text as positive, negative, or neutral sentiment.
Consider the overall tone, key phrases, and emotional indicators.
</instructions>

<text>
{{input_text}}
</text>

<formatting>
Output only one word: positive, negative, or neutral.
</formatting>
```

**Use when:**

- Task is self-explanatory
- No examples needed
- Single input, simple output

---

## Pattern 2: Task with Examples

For tasks that benefit from demonstrations:

```xml
<instructions>
You are a customer service classifier. Categorize each message into one of these categories: billing, technical, general, complaint.
</instructions>

<examples>
  <example>
    <input>My payment didn't go through</input>
    <output>billing</output>
  </example>
  <example>
    <input>The app keeps crashing</input>
    <output>technical</output>
  </example>
  <example>
    <input>This is the worst service I've ever experienced!</input>
    <output>complaint</output>
  </example>
</examples>

<message>
{{customer_message}}
</message>

<formatting>
Output only the category name, nothing else.
</formatting>
```

**Use when:**

- Classification or categorization tasks
- Need to demonstrate expected format
- Edge cases exist between categories

---

## Pattern 3: Multi-Document Processing

For tasks involving multiple input documents:

```xml
<instructions>
Compare the following documents and identify common themes and contradictions.
</instructions>

<documents>
  <document id="1" title="{{doc1_title}}">
    {{document_1}}
  </document>
  <document id="2" title="{{doc2_title}}">
    {{document_2}}
  </document>
  <document id="3" title="{{doc3_title}}">
    {{document_3}}
  </document>
</documents>

<formatting>
Structure your response with:
1. Common themes across all documents
2. Points of agreement
3. Contradictions or disagreements
4. Unique points per document
</formatting>
```

**Use when:**

- Multiple inputs need comparison
- Document identification matters
- Cross-referencing is required

---

## Pattern 4: Reasoning with Structured Output

For tasks requiring visible thinking and specific output format:

```xml
<instructions>
Analyze the business proposal and provide a recommendation.
Think through the analysis step-by-step before concluding.
</instructions>

<criteria>
  <criterion priority="1">Cost effectiveness</criterion>
  <criterion priority="2">Implementation timeline</criterion>
  <criterion priority="3">Risk level</criterion>
</criteria>

<proposal>
{{proposal_content}}
</proposal>

<formatting>
1. Analyze each criterion in <thinking> tags
2. Provide final recommendation in <recommendation> tags
3. Use one of: APPROVE, REJECT, or REVISE
</formatting>
```

**Use when:**

- Complex reasoning required
- Decision must be justified
- Explicit criteria guide evaluation

---

## Pattern 5: Conversational Context

For tasks involving conversation history:

```xml
<instructions>
You are a helpful assistant continuing a conversation.
Maintain consistency with previous exchanges.
</instructions>

<conversation_history>
  <message role="user">{{user_message_1}}</message>
  <message role="assistant">{{assistant_response_1}}</message>
  <message role="user">{{user_message_2}}</message>
</conversation_history>

<current_message>
{{current_user_message}}
</current_message>

<formatting>
Respond naturally, referencing previous context when relevant.
</formatting>
```

**Use when:**

- Multi-turn conversations
- Context from previous turns matters
- Consistency is important

---

## Pattern 6: Template with Variables

For reusable prompts with placeholders:

```xml
<instructions>
Generate a {{output_type}} about {{topic}} for {{audience}}.
</instructions>

<requirements>
  <length>{{word_count}} words</length>
  <tone>{{tone}}</tone>
  <format>{{format_type}}</format>
</requirements>

<additional_context>
{{any_extra_context}}
</additional_context>

<formatting>
Return the {{output_type}} only, no preamble or explanation.
</formatting>
```

**Use when:**

- Prompts will be reused
- Multiple parameters vary
- Standardized structure needed

---

## Pattern 7: Data Extraction

For extracting structured data from unstructured text:

```xml
<instructions>
Extract key information from the provided text.
Return structured data in JSON format.
</instructions>

<schema>
{
  "name": "string (required)",
  "email": "string (required, valid email format)",
  "phone": "string (optional)",
  "company": "string (optional)",
  "role": "string (optional)"
}
</schema>

<text>
{{unstructured_text}}
</text>

<formatting>
Return only valid JSON matching the schema.
Use null for optional fields that cannot be determined.
</formatting>
```

**Use when:**

- Extracting specific fields
- Output must be machine-parseable
- Schema defines expected structure

---

## Pattern 8: Constrained Generation

For creative tasks with specific constraints:

```xml
<instructions>
Write a short story following the given constraints.
</instructions>

<constraints>
  <length>Exactly 100 words</length>
  <genre>{{genre}}</genre>
  <must_include>{{required_elements}}</must_include>
  <avoid>{{elements_to_avoid}}</avoid>
  <style>{{writing_style}}</style>
</constraints>

<prompt>
{{story_prompt}}
</prompt>

<formatting>
Return only the story. Verify word count meets the requirement.
</formatting>
```

**Use when:**

- Creative output needed
- Hard constraints must be met
- Multiple rules apply simultaneously

---

## Nesting Patterns

### Hierarchical Content

```xml
<section name="Overview">
  <subsection name="Background">
    Content here...
  </subsection>
  <subsection name="Objectives">
    Content here...
  </subsection>
</section>
```

### Examples with Full Structure

```xml
<examples>
  <example type="positive">
    <input>...</input>
    <thinking>...</thinking>
    <output>...</output>
  </example>
  <example type="edge_case">
    <input>...</input>
    <thinking>...</thinking>
    <output>...</output>
  </example>
</examples>
```

### Conditional Content

```xml
<if_applicable context="{{has_previous_context}}">
  <previous_context>
    {{context_content}}
  </previous_context>
</if_applicable>
```

---

## Referencing Tags in Instructions

Always reference your tags explicitly in instructions:

**Good:**

```xml
<instructions>
Using the documents in the <documents> section, answer the question
in the <question> tags. Format your response as specified in <formatting>.
</instructions>
```

**Bad:**

```xml
<instructions>
Answer the question based on the provided information.
</instructions>
```

The explicit reference helps Claude understand the prompt structure.

---

## Common Tag Naming Conventions

| Purpose | Preferred Tags | Alternatives |
|---------|---------------|--------------|
| Task definition | `<instructions>` | `<task>`, `<role>` |
| Background info | `<context>` | `<background>`, `<situation>` |
| Input data | `<document>` | `<data>`, `<input>`, `<content>` |
| Examples | `<examples>`, `<example>` | `<samples>` |
| Output format | `<formatting>` | `<output_format>`, `<response_format>` |
| Constraints | `<rules>` | `<constraints>`, `<requirements>` |
| Thinking | `<thinking>` | `<analysis>`, `<reasoning>` |
| Final output | `<answer>` | `<output>`, `<response>`, `<result>` |

---

## Anti-Patterns to Avoid

### Inconsistent Tag Naming

**Bad:**

```xml
<instructions>...</instructions>
<Input>...</Input>  <!-- Different case -->
<FORMATTING>...</FORMATTING>  <!-- All caps -->
```

**Good:**

```xml
<instructions>...</instructions>
<input>...</input>
<formatting>...</formatting>
```

### Tags Without Purpose

**Bad:**

```xml
<wrapper>
  <inner_wrapper>
    <content_wrapper>
      Actual content
    </content_wrapper>
  </inner_wrapper>
</wrapper>
```

**Good:**

```xml
<content>
  Actual content
</content>
```

### Missing Closing Tags

Always ensure proper tag closure. Unclosed tags confuse parsing.

---

## Next Steps

- For complete tag library, see [../metadata/tag-reference.md](../metadata/tag-reference.md)
- For chain of thought patterns, see [cot-patterns.md](cot-patterns.md)
- For examples of transformations, see [../examples/](../examples/)
