# Complete XML Tag Reference

This reference provides a comprehensive library of XML tags used in prompt improvement, organized by purpose.

## Structural Organization Tags

These tags organize the main components of a prompt.

### `<instructions>`

**Purpose:** Define the task and behavioral guidelines

**Example:**

```xml
<instructions>
You are a helpful assistant that summarizes documents.
Always include key points and conclusions.
Keep summaries under 200 words.
</instructions>
```

---

### `<context>`

**Purpose:** Provide background information and relevant details

**Example:**

```xml
<context>
The user is a software developer working on a web application.
They need help debugging a performance issue.
</context>
```

---

### `<document>` / `<documents>`

**Purpose:** Wrap input data or reference material

**Example:**

```xml
<documents>
  <document id="1">
    First document content here...
  </document>
  <document id="2">
    Second document content here...
  </document>
</documents>
```

---

### `<example>` / `<examples>`

**Purpose:** Provide demonstration cases

**Example:**

```xml
<examples>
  <example>
    <input>What is 2 + 2?</input>
    <output>4</output>
  </example>
</examples>
```

---

### `<formatting>`

**Purpose:** Specify desired output format

**Example:**

```xml
<formatting>
Return your response as a JSON object with keys:
- summary: A brief overview
- key_points: An array of important points
- recommendation: Your suggested action
</formatting>
```

---

### `<data>`

**Purpose:** Wrap general data inputs

**Example:**

```xml
<data>
Name: John Doe
Age: 30
Location: New York
</data>
```

---

### `<rules>` / `<constraints>`

**Purpose:** Define rules or limitations

**Example:**

```xml
<rules>
1. Never reveal confidential information
2. Always cite sources
3. Keep responses under 500 words
</rules>
```

---

## Chain of Thought Tags

These tags structure Claude's reasoning process.

### `<thinking>`

**Purpose:** Internal reasoning/analysis steps (intermediate)

**Example:**

```xml
<thinking>
First, I need to understand what the user is asking.
They want to know the capital of France.
The capital of France is Paris.
</thinking>
```

---

### `<analysis>`

**Purpose:** Detailed analysis section

**Example:**

```xml
<analysis>
Breaking down the problem:
1. Identify the main issue
2. Consider possible causes
3. Evaluate solutions
</analysis>
```

---

### `<answer>` / `<final_answer>`

**Purpose:** Final response after thinking

**Example:**

```xml
<thinking>
The user asked about the capital of France.
Paris is the capital and largest city of France.
</thinking>
<answer>
The capital of France is Paris.
</answer>
```

---

### `<reasoning>`

**Purpose:** Explain the logic behind a decision

**Example:**

```xml
<reasoning>
I recommend Option A because:
1. It has the lowest cost
2. It meets all requirements
3. It has the fastest implementation time
</reasoning>
```

---

## Domain-Specific Tags

These tags are useful for specific use cases.

### `<transcript>`

**Purpose:** Wrap call or conversation transcripts

**Example:**

```xml
<transcript>
Agent: How can I help you today?
Customer: I have an issue with my order.
Agent: I'd be happy to help. What's the problem?
</transcript>
```

---

### `<json>`

**Purpose:** Wrap JSON output

**Example:**

```xml
<json>
{
  "status": "success",
  "data": {
    "id": 123,
    "name": "Example"
  }
}
</json>
```

---

### `<code>`

**Purpose:** Wrap code blocks

**Example:**

```xml
<code language="python">
def hello_world():
    print("Hello, World!")
</code>
```

---

### `<quotes>`

**Purpose:** Extracted quotations with references

**Example:**

```xml
<quotes>
  <quote source="Document 1, Page 5">
    "This is the relevant passage from the document."
  </quote>
</quotes>
```

---

### `<customer_email>`

**Purpose:** Wrap customer support emails

**Example:**

```xml
<customer_email>
Subject: Order Issue
Body: I ordered product #12345 but received the wrong item.
</customer_email>
```

---

### `<patient_record>`

**Purpose:** Medical domain patient information

**Example:**

```xml
<patient_record>
Name: Jane Smith
DOB: 1985-03-15
Chief Complaint: Headache for 3 days
</patient_record>
```

---

## Special Characters: CDATA

When your content includes special characters (`<`, `>`, `&`) or nested XML-like structures, use CDATA sections.

**Syntax:**

```xml
<document>
<![CDATA[
Content with special chars like < > & or even
<nested>XML-like</nested> structures that won't break parsing
]]>
</document>
```

---

## Nesting Patterns

### Hierarchical Content

```xml
<outer>
  <inner>
    Nested content here
  </inner>
</outer>
```

### Examples with Reasoning

```xml
<examples>
  <example>
    <input>User question here</input>
    <thinking>
      Step 1: Understand the question
      Step 2: Analyze the components
      Step 3: Formulate response
    </thinking>
    <output>Final answer here</output>
  </example>
</examples>
```

---

## Tag Selection Guide

| Use Case | Recommended Tags |
|----------|-----------------|
| Task definition | `<instructions>`, `<rules>` |
| Input data | `<document>`, `<data>`, `<context>` |
| Reasoning | `<thinking>`, `<analysis>`, `<reasoning>` |
| Output | `<answer>`, `<json>`, `<output>` |
| Examples | `<examples>`, `<example>` |
| Format spec | `<formatting>`, `<output_format>` |
| Quotations | `<quotes>`, `<quote>` |

---

## Best Practices

1. **Be consistent:** Use the same tag names throughout your prompts
2. **Use descriptive names:** Tag names should indicate content purpose
3. **Nest appropriately:** Use hierarchy for related content
4. **Reference tags explicitly:** Refer to tags in instructions (e.g., "Using the data in `<document>` tags...")
5. **Use CDATA for special content:** Prevent parsing issues with special characters
