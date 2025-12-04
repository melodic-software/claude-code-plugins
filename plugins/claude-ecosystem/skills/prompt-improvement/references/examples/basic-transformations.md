# Basic Transformations

This reference provides simple before/after examples demonstrating the 4-step improvement workflow.

## Example 1: Simple Classification

### Before (Original Prompt)

```text
Classify this email as spam or not spam.

Email: {{email}}
```

### After (Improved Prompt)

```xml
<instructions>
You are an email classification assistant. Your task is to analyze emails and determine whether they are spam or legitimate messages.

Analyze each email carefully before making your classification. Consider:
- Sender patterns and claims
- Urgency or pressure tactics
- Links or attachments
- Overall tone and purpose
</instructions>

<examples>
  <example>
    <input>
      Email: "You've won $1 million! Click here to claim your prize now!"
    </input>
    <thinking>
      Analyzing spam indicators:
      1. Unrealistic promise ("won $1 million")
      2. Urgency ("Click here now")
      3. No prior lottery participation mentioned
      4. Classic phishing pattern

      Conclusion: Multiple strong spam indicators.
    </thinking>
    <output>spam</output>
  </example>

  <example>
    <input>
      Email: "Hi team, reminder about our 3pm meeting tomorrow. Please review the attached agenda."
    </input>
    <thinking>
      Analyzing for spam indicators:
      1. Professional tone
      2. Specific, reasonable request (meeting reminder)
      3. Context suggests existing relationship
      4. No suspicious promises or urgency

      Conclusion: Legitimate business communication.
    </thinking>
    <output>not-spam</output>
  </example>
</examples>

<email>
{{email}}
</email>

<formatting>
First, analyze the email in <thinking> tags.
Then provide your classification as either "spam" or "not-spam" in <output> tags.
</formatting>
```

### What Changed

| Aspect | Before | After |
| -------- | -------- | ------- |
| Structure | Flat text | XML-organized sections |
| Instructions | Minimal | Detailed with criteria |
| Examples | None | 2 with reasoning |
| Reasoning | None | Explicit thinking tags |
| Format | Implied | Explicitly specified |

---

## Example 2: Text Summarization

### Before (Original Prompt)

```text
Summarize this article in 3 sentences.

{{article}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a professional summarizer. Create a concise 3-sentence summary of the provided article.

Your summary should:
- Capture the main point or thesis
- Include the most important supporting details
- Be exactly 3 sentences (no more, no less)
- Use clear, direct language
</instructions>

<examples>
  <example>
    <input>
      Article: "Scientists at MIT have developed a new battery technology that could triple the range of electric vehicles. The breakthrough involves using solid-state electrolytes instead of liquid ones, which are both safer and more energy-dense. The team expects commercial applications within 5 years, though manufacturing challenges remain. Several major automakers have already expressed interest in licensing the technology."
    </input>
    <thinking>
      Key points to include:
      1. Main news: MIT scientists developed new battery tech
      2. Impact: Could triple EV range
      3. Timeline: 5 years to commercial use
      4. Interest: Automakers interested

      Condensing to 3 sentences covering what, why it matters, and outlook.
    </thinking>
    <output>
      MIT researchers have developed a solid-state battery technology that could triple electric vehicle range. The new approach is both safer and more energy-dense than current liquid electrolyte batteries. With automaker interest already secured, commercial applications are expected within five years.
    </output>
  </example>
</examples>

<article>
{{article}}
</article>

<formatting>
First, identify key points in <thinking> tags.
Then provide exactly 3 sentences in <output> tags.
</formatting>
```

### What Changed

| Aspect | Before | After |
| -------- | -------- | ------- |
| Constraint clarity | "3 sentences" | "exactly 3 sentences (no more, no less)" |
| Guidance | None | What to include in summary |
| Example | None | 1 with reasoning |
| Process | Implied | Explicit thinking step |

---

## Example 3: Question Answering

### Before (Original Prompt)

```text
Answer this question based on the document.

Document: {{document}}
Question: {{question}}
```

### After (Improved Prompt)

```xml
<instructions>
You are a careful reader and question answerer. Answer questions based solely on the information provided in the document.

Rules:
- Only use information from the provided document
- If the answer isn't in the document, say "The document does not contain this information"
- Quote relevant passages to support your answer
- Be concise but complete
</instructions>

<examples>
  <example>
    <document>
      The Amazon rainforest produces about 20% of the world's oxygen and contains 10% of all species on Earth. It spans 9 countries and covers approximately 5.5 million square kilometers.
    </document>
    <question>How much oxygen does the Amazon produce?</question>
    <thinking>
      Searching document for oxygen information...
      Found: "produces about 20% of the world's oxygen"
      This directly answers the question.
    </thinking>
    <answer>
      The Amazon rainforest produces about 20% of the world's oxygen.

      Source: "The Amazon rainforest produces about 20% of the world's oxygen"
    </answer>
  </example>

  <example>
    <document>
      The Amazon rainforest produces about 20% of the world's oxygen and contains 10% of all species on Earth.
    </document>
    <question>What is the average temperature in the Amazon?</question>
    <thinking>
      Searching document for temperature information...
      No mention of temperature found.
      Must indicate information not available.
    </thinking>
    <answer>
      The document does not contain this information.
    </answer>
  </example>
</examples>

<document>
{{document}}
</document>

<question>
{{question}}
</question>

<formatting>
First, search for relevant information in <thinking> tags.
Then provide your answer with supporting quotes in <answer> tags.
</formatting>
```

### What Changed

| Aspect | Before | After |
| -------- | -------- | ------- |
| Source constraint | Implied | Explicit "only use document" |
| Missing info handling | None | Explicit fallback response |
| Evidence | None | Required quotes |
| Examples | None | 2 (found and not found) |

---

## Example 4: Sentiment Analysis

### Before (Original Prompt)

```text
What is the sentiment of this text? Positive, negative, or neutral?

{{text}}
```

### After (Improved Prompt)

```xml
<instructions>
Analyze the sentiment of the provided text and classify it as positive, negative, or neutral.

Consider:
- Overall emotional tone
- Key sentiment-bearing words and phrases
- Context that may modify meaning (e.g., sarcasm, hedging)
- Intensity of sentiment expression
</instructions>

<examples>
  <example>
    <input>I absolutely love this product! Best purchase I've ever made.</input>
    <thinking>
      Sentiment indicators:
      - "absolutely love" - strong positive
      - "Best purchase ever" - superlative positive
      - No negative qualifiers
      - Intensity: High
    </thinking>
    <output>positive</output>
  </example>

  <example>
    <input>The product works as described. Shipping was on time.</input>
    <thinking>
      Sentiment indicators:
      - "works as described" - factual, no emotion
      - "on time" - meeting expectations, not exceeding
      - No positive or negative qualifiers
      - Intensity: None
    </thinking>
    <output>neutral</output>
  </example>

  <example>
    <input>Complete waste of money. Broke after two days.</input>
    <thinking>
      Sentiment indicators:
      - "Complete waste" - strong negative
      - "Broke after two days" - negative experience
      - No positive aspects mentioned
      - Intensity: High
    </thinking>
    <output>negative</output>
  </example>
</examples>

<text>
{{text}}
</text>

<formatting>
Analyze in <thinking> tags, then output only "positive", "negative", or "neutral" in <output> tags.
</formatting>
```

### What Changed

| Aspect | Before | After |
| -------- | -------- | ------- |
| Analysis criteria | None | Listed considerations |
| Examples | None | 3 (one per category) |
| Thinking process | Implied | Explicit with indicators |
| Output format | Loose | Strictly one word |

---

## Common Transformation Patterns

### Pattern 1: Add Structure

```text
Before: Flat text blob
After: XML sections (<instructions>, <examples>, <formatting>)
```

### Pattern 2: Add Examples

```text
Before: No examples
After: 2-3 examples with reasoning
```

### Pattern 3: Explicit Constraints

```text
Before: "Summarize in 3 sentences"
After: "exactly 3 sentences (no more, no less)"
```

### Pattern 4: Thinking Process

```text
Before: Direct output expected
After: <thinking> before <output>
```

### Pattern 5: Format Specification

```text
Before: Implied format
After: Explicit <formatting> section
```

---

## Next Steps

- For complex prompts, see [advanced-transformations.md](advanced-transformations.md)
- For domain-specific examples, see [domain-specific.md](domain-specific.md)
- For pattern details, see [../patterns/](../patterns/)
