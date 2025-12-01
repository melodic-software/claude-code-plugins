---
description: Get Gemini's independent analysis on recent context or specified topic
argument-hint: [topic or context to review]
allowed-tools: Bash
---

# Gemini Second Opinion Command

Get Gemini's independent perspective on a topic, plan, or piece of work.

## Usage

```text
/google-ecosystem:gemini-second-opinion [topic]
```

## Arguments

- `$ARGUMENTS` (optional): Topic or context to review. If empty, reviews general context.

## Examples

- `/google-ecosystem:gemini-second-opinion Is this database schema normalized correctly?`
- `/google-ecosystem:gemini-second-opinion Review my approach to error handling in this module`
- `/google-ecosystem:gemini-second-opinion Should I use microservices or monolith for this project?`
- `/google-ecosystem:gemini-second-opinion Validate my security assessment`

## Execution

### Build Review Prompt

```bash
topic="${ARGUMENTS:-the current context}"

prompt="REVIEW MODE (read-only): Provide an independent analysis.

TOPIC: $topic

Please provide:

1. **Your Assessment**: What is your independent view on this?

2. **Potential Issues**: What concerns or risks do you see?

3. **Alternative Approaches**: What other options should be considered?

4. **Recommendations**: What would you suggest?

5. **Confidence Level**: How confident are you in this assessment? (High/Medium/Low)

Be direct and specific. If you disagree with an apparent approach, say so clearly.

DO NOT modify any files. This is analysis only."
```

### Execute Query

```bash
result=$(gemini "$prompt" --output-format json)
```

### Parse Response

```bash
response=$(echo "$result" | jq -r '.response // "No response received"')
tokens=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.total) | add // 0')
model=$(echo "$result" | jq -r '.stats.models | keys[0] // "unknown"')

# Check for errors
error=$(echo "$result" | jq -r '.error.message // empty')
if [ -n "$error" ]; then
  echo "Error: $error"
  exit 1
fi
```

## Output Format

Present Gemini's perspective:

```markdown
# Gemini Second Opinion

**Topic**: {topic}
**Model**: {model}

---

{response}

---
*Independent analysis by Gemini CLI | {tokens} tokens*
```

## Use Cases

### Validate a Plan

Before executing a significant change, get Gemini's take:

```text
/google-ecosystem:gemini-second-opinion I'm planning to refactor auth to use JWT instead of sessions. Good idea?
```

### Cross-Check Analysis

After Claude provides analysis, validate:

```text
/google-ecosystem:gemini-second-opinion Claude identified 3 security issues in auth.ts. Are there others?
```

### Architecture Decision

Get input on technical choices:

```text
/google-ecosystem:gemini-second-opinion Should this use GraphQL or REST?
```

### Code Review Supplement

Add another perspective to code reviews:

```text
/google-ecosystem:gemini-second-opinion Is this error handling approach robust?
```

## Notes

- Uses "REVIEW MODE" prefix to ensure read-only analysis
- Provides structured output with assessment, issues, alternatives
- Includes confidence level for transparency
- Two AI perspectives catch more issues than one
