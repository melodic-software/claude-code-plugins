# Context Layers: What's in Your Agent's Mind

Understanding the seven layers of context helps you optimize where to invest tokens for maximum impact.

## The Seven Layers (Priority Order)

| Priority | Layer | Description | Token Impact |
| ---------- | ------- | ------------- | -------------- |
| 1 | System Prompt | The law of the agent | High (shapes all reasoning) |
| 2 | User Prompt | Current task instructions | High (immediate focus) |
| 3 | Tool Definitions | Available capabilities | Medium (capability awareness) |
| 4 | Tool Results | Output from tool calls | Very High (working memory) |
| 5 | Conversation History | Previous turns | Medium (compressed over time) |
| 6 | Files Read | Codebase content | High (reference material) |
| 7 | Memory Files | CLAUDE.md imports | Medium (persistent guidance) |

## Layer-by-Layer Analysis

### Layer 1: System Prompt

The system prompt is the "law" of your agent - highest priority instructions that shape all subsequent reasoning.

**Optimization:**

- Keep focused on current purpose
- Avoid contradictory instructions
- Use agent experts for specialized system prompts

**Impact:** Every token in system prompt influences every decision.

### Layer 2: User Prompt

The current task instructions from the user.

**Optimization:**

- Clear, specific instructions
- Include constraints and success criteria
- Reference relevant context (files, patterns)

**Impact:** Directs the agent's immediate focus and actions.

### Layer 3: Tool Definitions

The capabilities available to the agent (tools, MCP servers).

**Optimization:**

- Only load needed MCP servers
- Remove default .mcp.json bloat
- Use focused tool access per agent

**Impact:** Each MCP server can consume 2-5% of context window.

### Layer 4: Tool Results

Output from tool calls during execution - the largest token consumer.

**Optimization:**

- Control output verbosity (output styles)
- Use focused tool parameters (limit, offset)
- Avoid verbose Bash output
- Summarize large results

**Impact:** Often 50-70% of context during active work.

### Layer 5: Conversation History

Previous turns in the conversation, compressed over time.

**Optimization:**

- Use fresh instances for new task types
- Don't rely on old context for current work
- Clear context periodically (/clear)

**Impact:** Accumulates and compresses, can cause context rot.

### Layer 6: Files Read

Codebase content loaded into context.

**Optimization:**

- Read specific files, not directories
- Use limit/offset for large files
- Load on-demand, not "just in case"
- Delegate file-heavy research

**Impact:** Can quickly consume context if loading entire codebases.

### Layer 7: Memory Files

CLAUDE.md and its imports.

**Optimization:**

- Keep CLAUDE.md minimal
- Use conditional imports
- Delegate to priming commands
- Avoid always-on bloat

**Impact:** Loaded every instance, compounds over time.

## Context Consumption Visualization

```text
Context Window (100%)
| ================================================================= |
| System Prompt (5-10%) |
| ------------------------------------------------------------------ |
| Tool Definitions (5-15%) |
| ------------------------------------------------------------------ |
| User Prompt (2-5%) |
| ------------------------------------------------------------------ |
| Tool Results (30-50%)        <- Largest consumer during work |
| ------------------------------------------------------------------ |
| Conversation History (10-20%) |
| ------------------------------------------------------------------ |
| Files Read (15-30%) |
| ------------------------------------------------------------------ |
| Memory Files (5-10%) |
| ================================================================= |
```markdown

## Optimization Strategies by Layer

### High-Impact Optimizations

1. **Tool Results**: Use output styles, limit parameters, delegation
2. **Files Read**: On-demand loading, focused reads, delegation
3. **Tool Definitions**: Remove unused MCP servers

### Medium-Impact Optimizations

1. **Memory Files**: Minimal CLAUDE.md, conditional imports
2. **Conversation History**: Fresh instances, periodic clears

### Foundational (Always Optimize)

1. **System Prompt**: Focused, non-contradictory
2. **User Prompt**: Clear, specific, constrained

## The Context Flow

```text
Static Context (always present)
  System Prompt
  Tool Definitions
  Memory Files
        |
        v
Dynamic Context (task-specific)
  User Prompt
  Files Read
  Tool Results
        |
        v
Accumulated Context (grows over time)
  Conversation History
```yaml

## Key Insight

> "Your agent is brilliant but blind. It can only see what's in its context window. Every token competes for attention."

Understanding these layers helps you invest tokens where they have maximum impact for the current task.

---

**Cross-References:**

- @rd-framework.md - Reduce and Delegate strategies
- @context-rot-vs-pollution.md - When context goes wrong
- @minimum-context-principle.md - Include only what's necessary
