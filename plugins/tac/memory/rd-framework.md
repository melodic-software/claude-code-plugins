# The R&D Framework for Context Engineering

The R&D Framework is the foundation of elite context engineering. There are only two ways to manage your context window: **Reduce** and **Delegate**.

## The Framework

| Strategy | Purpose | When to Use |
| ---------- | --------- | ------------- |
| **R - Reduce** | Remove unnecessary context | Verbose outputs, irrelevant files, bloated memory |
| **D - Delegate** | Offload to specialized agents | Complex subtasks, research, parallel work |

Every context optimization technique fits into one or both of these buckets.

## Reduce: Strategies for Trimming Context

### What to Reduce

1. **Verbose Tool Outputs**
   - Long command outputs consuming tokens
   - Full file contents when summaries suffice
   - Repeated information from multiple tool calls

2. **Conversation History Accumulation**
   - Multi-turn conversations building context rot
   - Outdated instructions from earlier turns
   - Failed attempts still in context

3. **"Just in Case" Loading**
   - Files loaded that might be relevant
   - Full directories instead of specific files
   - All MCP servers instead of needed ones

4. **Bloated Memory Files**
   - CLAUDE.md that grew over time
   - Contradictory or outdated guidance
   - Information not needed for every task

### How to Reduce

```text
Before: Load entire codebase -> Analyze -> Implement
After:  Load README only -> Analyze scope -> Load specific files -> Implement
```markdown

Key techniques:

- Use `/context` to measure current state
- Remove default .mcp.json files
- Use context priming over always-on memory
- Start fresh instances for new task types
- Control output verbosity (output styles)

## Delegate: Strategies for Offloading Context

### When to Delegate

1. **Complex Subtasks**
   - Research requiring different context
   - Documentation fetching
   - Code analysis in isolation

2. **Parallel Work**
   - Multiple independent tasks
   - Work that doesn't need shared state
   - Background processing

3. **Domain-Specific Tasks**
   - Tasks requiring specialized knowledge
   - Work better handled by expert agents
   - Focused tool access requirements

### How to Delegate

```text
Primary Agent (full context) -> Sub-Agent (focused context) -> Result
```markdown

Delegation patterns:

- Use Task tool with specific subagent types
- Launch background Claude instances
- Create agent experts for domains
- Use spec files for handoff

## The Context Sweet Spot

```text
Too Little Context          Sweet Spot           Too Much Context
| ---------------------- | ================= | ---------------------- |
  Agent lacks info       Optimal perf       Agent overwhelmed
  to complete task       for the task       with irrelevant info
```yaml

The sweet spot is the range where your agent performs optimally for the task at hand. Elite context engineering means consistently hitting this range.

## Measuring Success

| Metric | Description | Target |
| -------- | ------------- | -------- |
| Signal-to-Noise Ratio | Information value / tokens consumed | Maximize |
| Fresh Instance Rate | How often new instances started | High for complex work |
| Delegation Rate | Work offloaded to sub-agents | Match task complexity |
| Context Utilization | Current usage vs limit | Stay in sweet spot |

## The Guiding Questions

Before adding context, ask:

1. Is this context necessary for this specific task?
2. Can this be loaded on-demand instead of pre-loaded?
3. Should this be delegated to a specialized sub-agent?
4. Am I starting fresh or carrying baggage?

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| Context Stuffing | Loading everything "just in case" | Load on-demand |
| Long Conversations | Multi-turn context accumulation | Fresh instances |
| Verbose Outputs | Tool results consuming tokens | Output style control |
| Unscoped Imports | Loading all memory at once | Conditional imports |

## Key Quote

> "Context is the most important leverage point of agentic coding. The agent's mind is finite - treat context as precious real estate."

---

**Cross-References:**

- @context-layers.md - Understanding what's in your context window
- @context-rot-vs-pollution.md - Distinguishing context problems
- @context-priming-patterns.md - Dynamic context loading
