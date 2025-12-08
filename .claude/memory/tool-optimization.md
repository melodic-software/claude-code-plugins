# Tool Optimization Principles

**Token Budget:** ~2,200 tokens | **Load Type:** Context-dependent (load when designing or debugging tools)

This document contains principles for designing effective tools for AI agents, extracted from Anthropic's engineering research and best practices.

**Source:** Use docs-management skill to find "writing-tools-for-agents" documentation

## Core Principle

Tools for AI agents are fundamentally different from traditional software functions. Agents have limited context (attention budget), so tools must be designed with agent-specific affordances in mind. Tools should enable agents to subdivide and solve tasks naturally while minimizing context consumption.

## Choosing the Right Tools

### More Tools != Better Outcomes

A common error is wrapping existing software functionality or API endpoints without considering whether tools are appropriate for agents. Agents have distinct "affordances" - different ways of perceiving potential actions.

**Key insight:** LLM agents have limited context (how much information they can process at once), whereas computer memory is cheap and abundant.

### Design for Context Efficiency

**Example:** Searching for a contact in an address book

- **Bad**: `list_contacts` tool returns ALL contacts - agent wastes context reading irrelevant entries
- **Good**: `search_contacts` or `message_contact` tools - agent skips directly to relevant information

Traditional software can efficiently store and process lists one at a time. Agents waste context by reading through irrelevant information token-by-token.

### Consolidate Functionality

Tools can handle multiple discrete operations (or API calls) under the hood:

**Instead of:**

- `list_users`, `list_events`, `create_event` tools

**Consider:**

- `schedule_event` tool which finds availability and schedules an event

**Instead of:**

- `read_logs` tool

**Consider:**

- `search_logs` tool which only returns relevant log lines with surrounding context

**Instead of:**

- `get_customer_by_id`, `list_transactions`, `list_notes` tools

**Consider:**

- `get_customer_context` tool which compiles all customer's recent & relevant information at once

Each tool should have a clear, distinct purpose. Tools should enable agents to subdivide tasks the way humans would, while reducing context consumed by intermediate outputs.

**Principle:** Build a few thoughtful tools targeting specific high-impact workflows, matching your evaluation tasks, then scale up.

## Namespacing Tools

When agents have access to dozens of MCP servers and hundreds of tools, overlapping functionality creates confusion.

**Solution:** Namespace tools by grouping related tools under common prefixes or suffixes.

**Examples:**

- By service: `asana_search`, `jira_search`
- By resource: `asana_projects_search`, `asana_users_search`

**Important:** Choosing between prefix- and suffix-based namespacing can have non-trivial effects on tool-use evaluations. Effects vary by LLM. Choose naming scheme based on your own evaluations.

**Benefit:** By selectively implementing tools whose names reflect natural task subdivisions, you:

- Reduce the number of tools and tool descriptions loaded into context
- Offload agentic computation from agent's context back into tool calls
- Reduce overall risk of mistakes

## Returning Meaningful Context

Tool implementations should return only high-signal information back to agents.

### Prefer Natural Language Over Technical IDs

**Priority order:**

1. Natural language names, terms, identifiers
2. Semantically meaningful identifiers (even 0-indexed ID schemes)
3. Cryptic identifiers (UUIDs, technical codes)

**Why:** Agents handle natural language names significantly better than cryptic identifiers. Resolving UUIDs to meaningful language improves precision in retrieval tasks and reduces hallucinations.

**Examples:**

- **Avoid**: `uuid`, `256px_image_url`, `mime_type`
- **Prefer**: `name`, `image_url`, `file_type`

### Response Format Flexibility

When agents need both natural language and technical identifiers (for downstream tool calls), expose a `response_format` parameter:

```typescript
enum ResponseFormat {
  DETAILED = "detailed",  // Includes IDs for further tool calls
  CONCISE = "concise"     // Natural language only, token-efficient
}
```

**Example benefit:** Slack thread responses

- `detailed` format: Includes `thread_ts`, `channel_id`, `user_id` (required for downstream calls) - 206 tokens
- `concise` format: Thread content only - 72 tokens (~1/3 reduction)

### Response Structure Matters

Tool response structure (XML, JSON, Markdown) can impact evaluation performance. LLMs are trained on next-token prediction and tend to perform better with formats matching their training data. Optimal structure varies by task and agent - evaluate and choose based on your specific use case.

## Token Efficiency

Optimize both quality AND quantity of context returned.

### Pagination, Filtering, Truncation

Implement some combination of:

- **Pagination**: Limit results per page
- **Range selection**: Allow agents to request specific ranges
- **Filtering**: Let agents filter before retrieving
- **Truncation**: Cut off at sensible limits with helpful instructions

**Default limits:** Claude Code restricts tool responses to 25,000 tokens by default.

### Helpful Truncation Messages

When truncating responses, steer agents toward token-efficient strategies:

**Example truncation message:**
> "Results truncated. To see more, use filters or pagination. Consider making targeted searches instead of broad queries."

### Error Message Engineering

Error messages should communicate specific, actionable improvements rather than opaque codes or tracebacks.

**Unhelpful:**

```text
Error 400: Invalid parameter
```

**Helpful:**

```text
Invalid 'date' parameter: expected format 'YYYY-MM-DD' (e.g., '2025-01-15'), but received '1/15/2025'. Please reformat the date and try again.
```

Error responses can steer agents toward correct tool usage and provide examples of properly formatted inputs.

## Tool Description Engineering

Tool descriptions and specs are loaded into agent context and collectively steer tool-calling behaviors. This is one of the most effective methods for improving tool performance.

### Write for New Hires

Think of how you would describe your tool to a new team member. Consider implicit context you bring:

- Specialized query formats
- Definitions of niche terminology
- Relationships between underlying resources

**Make it explicit.** Don't assume shared context.

### Avoid Ambiguity

- Use unambiguous parameter names: `user_id` instead of `user`
- Clearly describe (and enforce with strict data models) expected inputs and outputs
- Include examples in tool descriptions when helpful

### Measure Impact

With evaluation, measure the impact of prompt engineering. Even small refinements to tool descriptions can yield dramatic improvements. Claude Sonnet 3.5 achieved state-of-the-art performance on SWE-bench Verified after precise refinements to tool descriptions, dramatically reducing error rates.

## Evaluation-Driven Improvement

**Process:**

1. Build evaluation tasks grounded in real-world uses
2. Measure how well agents use your tools
3. Analyze results: tool calling metrics, errors, token usage
4. Iteratively refine tools based on failure modes
5. Use agents (like Claude Code) to analyze transcripts and improve tools automatically

**Metrics to track:**

- Top-level accuracy
- Total runtime of tool calls and tasks
- Total number of tool calls
- Total token consumption
- Tool errors (and what causes them)

**Common issues:**

- Many redundant tool calls -> Consider pagination/range selection improvements
- Tool errors for invalid parameters -> Improve descriptions or add examples
- Agents appending unnecessary data (e.g., year to queries) -> Refine tool descriptions

## Tool Constraints

For critical tool constraints including the **Read-before-Edit requirement**, see CLAUDE.md Critical Rules section. This file focuses on tool design principles; authoritative tool constraints are documented in CLAUDE.md.

## Summary

Effective tools for agents:

- Are intentionally and clearly defined
- Use agent context judiciously (return only high-signal information)
- Can be combined in diverse workflows
- Enable agents to intuitively solve real-world tasks
- Consolidate functionality (handle multiple operations efficiently)
- Return meaningful context (natural language > cryptic IDs)
- Optimize for token efficiency (pagination, filtering, truncation)
- Have helpful error messages (actionable guidance, examples)
- Are described clearly (write for new hires, avoid ambiguity)

**Source Documentation:**

- Use docs-management skill to find "writing-tools-for-agents" documentation
- [Anthropic Developer Guide: Tool Use Best Practices](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use#best-practices-for-tool-definitions)

---

**Last Updated:** 2025-12-06
