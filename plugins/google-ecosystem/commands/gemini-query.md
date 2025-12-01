---
description: Send a quick headless query to Gemini CLI and display the response with stats
argument-hint: <prompt>
allowed-tools: Bash
---

# Gemini Query Command

Execute a quick headless query to Gemini CLI and display the response.

## Usage

```text
/google-ecosystem:gemini-query <prompt>
```

## Examples

- `/google-ecosystem:gemini-query What is the capital of France?`
- `/google-ecosystem:gemini-query Explain async/await in JavaScript`
- `/google-ecosystem:gemini-query Review this error: TypeError: Cannot read property 'x' of undefined`

## Execution

Run the query using Gemini CLI headless mode:

```bash
result=$(gemini "$ARGUMENTS" --output-format json 2>&1)
```

## Output

Parse and present the response:

1. **Response**: The main AI-generated content from `.response`
2. **Stats**: Token usage, model used, latency from `.stats`
3. **Errors**: Any error messages from `.error`

### Response Extraction

```bash
# Extract response
response=$(echo "$result" | jq -r '.response // "No response"')

# Extract stats
tokens=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.total) | add // 0')
cached=$(echo "$result" | jq '.stats.models | to_entries | map(.value.tokens.cached) | add // 0')
models=$(echo "$result" | jq -r '.stats.models | keys | join(", ") | if . == "" then "unknown" else . end')
latency=$(echo "$result" | jq '.stats.models | to_entries | map(.value.api.totalLatencyMs) | add // 0')

# Check for errors
error=$(echo "$result" | jq -r '.error.message // empty')
```

## Format Output

Present the results in a clean format:

```markdown
## Gemini Response

{response}

---
**Stats**: {tokens} tokens ({cached} cached) | Model: {models} | Latency: {latency}ms
```

If there's an error:

```markdown
## Error

**Type**: {error_type}
**Message**: {error_message}
```

## Notes

- Uses `--output-format json` for structured parsing
- Displays both response and usage statistics
- Handles errors gracefully with helpful messages
