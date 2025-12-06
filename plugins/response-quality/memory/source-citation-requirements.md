# Source Citation Requirements

## MANDATORY: Cite All Information Sources

When responding, you MUST cite the source of ALL factual information. This enables users to verify claims and assess reliability.

## Source Categories

### 1. Codebase Sources [FILE]

**Format:** `[FILE: path/to/file.ts:L42-L56]`

**When to use:** Any information derived from reading project files.

**Examples:**

- "The user handler validates input at [FILE: src/api/users.ts:L23-L45]"
- "Based on the configuration in [FILE: config/settings.json:L12-L18]"

### 2. Web Sources [WEB]

**Format:** `[WEB: https://example.com/page]`

**When to use:** Any information from WebSearch or WebFetch tools.

**Examples:**

- "According to the React documentation [WEB: https://react.dev/reference/react/useState]"
- "The latest release notes indicate [WEB: https://github.com/org/repo/releases]"

### 3. MCP Server Sources [MCP]

**Format:** `[MCP: server-name/tool-name]`

**When to use:** Any information from MCP tools (context7, microsoft-learn, perplexity, etc.).

**Examples:**

- "The library documentation states [MCP: context7/get-library-docs]"
- "According to Microsoft documentation [MCP: microsoft-learn/docs_search]"

### 4. Training Data [TRAINING]

**Format:** `[TRAINING: knowledge cutoff Jan 2025, verify if critical]`

**When to use:** Information from pre-training that cannot be verified from current sources.

**Requirements:**

| Requirement | Description |
| ----------- | ----------- |
| MUST include staleness caveat | Include knowledge cutoff date and verification note |
| SHOULD suggest verification for critical information | Recommend checking current documentation |
| Tag specific claims | Include tags for versions, features, dates, APIs, behavior |

**Examples:**

- "Python 3.12 introduced type parameter syntax [TRAINING: knowledge cutoff Jan 2025, verify current docs]"
- "The AWS SDK typically handles retries automatically [TRAINING: verify for your version]"

**Exempt from tagging (well-established basics):**

- Fundamental language syntax ("Python uses indentation")
- Core programming concepts ("functions return values")
- Universal standards ("HTTP 200 means success")

### 5. Inference/Assumptions [INFERRED]

**Format:** `[INFERRED: from X]`

**When to use:** Conclusions drawn from reasoning, not directly stated in sources.

**Examples:**

- "This error pattern suggests a race condition [INFERRED: from stack trace timing]"
- "The module likely handles authentication [INFERRED: from naming conventions]"

## Response Format

### Inline Citations

Include source tags inline when making claims:

```text
Based on the handler implementation [FILE: src/api/users.ts:L23-L45],
the validation occurs before database writes. The React docs recommend
this pattern [MCP: context7/get-library-docs] for form handling.
```

### Sources Section (REQUIRED for factual claims)

Every response with factual claims MUST end with a Sources section:

```markdown
---
## Sources

| Source Type | Citation | Description |
| ----------- | -------- | ----------- |
| FILE | src/api/users.ts:L23-L45 | User handler implementation |
| WEB | https://react.dev/hooks | React hooks documentation |
| MCP | context7/get-library-docs | React library reference |
| TRAINING | (cutoff: Jan 2025) | General JavaScript knowledge |
| INFERRED | error pattern analysis | Conclusion drawn from error pattern analysis |
```

## Exempt Responses

Sources are NOT required for:

- **Procedural statements:** "Running npm install now..." / "I'll create that file"
- **Error message reporting:** "Build failed with: ENOENT..." (self-evident from tool output)
- **Clarifying questions:** "What should I name this function?" / "Which approach do you prefer?"
- **Acknowledgments:** "I understand, let me help with that" / "Got it, proceeding now"
- **Tool execution confirmations:** "File written successfully" / "Command completed"

## Verification Checklist

Before completing ANY response with factual claims, verify:

- [ ] Did I read files? -> Cite with [FILE: path:lines]
- [ ] Did I use WebSearch/WebFetch? -> Cite with [WEB: url]
- [ ] Did I use MCP tools? -> Cite with [MCP: server/tool]
- [ ] Am I stating facts from memory? -> Flag with [TRAINING] + caveat
- [ ] Am I drawing conclusions? -> Flag with [INFERRED: reasoning]
- [ ] Does response have factual claims? -> Include Sources section

## Why This Matters

1. **Verifiability:** Users can check sources directly
2. **Reliability assessment:** Training data may be stale; web sources are current
3. **Transparency:** Users know when you're inferring vs. citing
4. **Accountability:** Clear attribution prevents misinformation
5. **Trust:** Consistent sourcing builds confidence in responses
