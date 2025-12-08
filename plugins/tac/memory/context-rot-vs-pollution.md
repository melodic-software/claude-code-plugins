# Context Rot vs Pollution vs Toxic Context

Understanding the three types of context problems helps you diagnose and fix agent performance issues.

## The Three Context Problems

| Problem | Description | Source | Impact |
| --------- | ------------- | -------- | -------- |
| **Context Rot** | Old, stale context | Long conversations, old instances | Outdated decisions |
| **Context Pollution** | Irrelevant context | "Just in case" loading | Diluted focus |
| **Toxic Context** | Conflicting context | Contradictory instructions | Inconsistent behavior |

## Context Rot

**Definition:** Old, stale information consuming context window space and guiding decisions based on outdated state.

### Symptoms

- Agent references code patterns that no longer exist
- Agent tries to use deprecated APIs
- Agent's understanding doesn't match current codebase state
- Confusion about "current" vs "previous" state

### Causes

- Long-running conversations without refresh
- Conversation history with outdated information
- Multi-turn sessions spanning significant code changes
- Old tool results still in context

### Detection

```text
Red Flags:
- "As we discussed earlier..." (referencing stale context)
- "Based on the previous implementation..." (may be changed)
- Agent suggests patterns you've already moved away from
- Agent confused about current file state
```markdown

### Solutions

| Solution | When to Use |
| ---------- | ------------- |
| Fresh instance | New task type or significant changes |
| `/clear` command | Reset within same session |
| Delegation | Offload to fresh sub-agent |
| Context priming | Reload current state explicitly |

## Context Pollution

**Definition:** Irrelevant context added that dilutes the agent's focus and wastes token budget.

### Symptoms

- Agent struggles to focus on current task
- Agent mentions unrelated files or concepts
- Responses include irrelevant information
- Agent takes longer to find relevant patterns

### Causes

- Loading files "just in case"
- All MCP servers loaded by default
- Bloated CLAUDE.md with everything
- Full codebase reads instead of focused

### Detection

```text
Red Flags:
- Agent references files unrelated to task
- Verbose responses with tangential information
- "I also noticed..." about irrelevant areas
- High context consumption, low task relevance
```markdown

### Solutions

| Solution | When to Use |
| ---------- | ------------- |
| R&D Framework | Apply Reduce and Delegate |
| Focused loading | Load specific files only |
| Remove MCP bloat | Delete default .mcp.json |
| Minimal CLAUDE.md | Keep only universals |

## Toxic Context

**Definition:** Conflicting or confusing context that causes the agent to produce inconsistent or contradictory outputs.

### Symptoms

- Agent behavior contradicts instructions
- Different approaches in same response
- Confusion about which pattern to follow
- Oscillating between conflicting strategies

### Causes

- Contradictory instructions in prompts
- Memory files with conflicting guidance
- Old instructions conflicting with new
- Multiple sources saying different things

### Detection

```text
Red Flags:
- "On one hand... on the other hand..." without resolution
- Agent asks for clarification about contradictions
- Different parts of response conflict
- Agent switches patterns mid-task
```markdown

### Solutions

| Solution | When to Use |
| ---------- | ------------- |
| Clear prompts | Remove contradictions |
| Isolation | Use fresh instance with single source |
| Review memory | Audit for conflicts |
| Single authority | One source of truth per topic |

## Diagnosis Flowchart

```text
Agent performing poorly?
        |
        v
Is agent referencing outdated info? --> Yes --> Context Rot
        |                                         (Fresh instance)
        No
        |
        v
Is agent unfocused/tangential? --> Yes --> Context Pollution
        |                                   (Apply R&D)
        No
        |
        v
Is agent contradicting itself? --> Yes --> Toxic Context
        |                                   (Clear conflicts)
        No
        |
        v
Other issue (model, tools, prompt quality)
```yaml

## Prevention Strategies

### Prevent Context Rot

1. Start fresh instances for new task types
2. Use delegation for long-running work
3. Periodically clear conversation history
4. Reload current state with priming commands

### Prevent Context Pollution

1. Load files on-demand, not pre-emptively
2. Remove unused MCP servers
3. Keep CLAUDE.md minimal
4. Use focused tool parameters

### Prevent Toxic Context

1. Single source of truth per topic
2. Regular memory file audits
3. Clear, non-contradictory prompts
4. Versioned documentation

## The Health Check

Before starting complex work, verify:

- [ ] Am I starting with fresh context? (no rot)
- [ ] Is every piece of loaded context relevant? (no pollution)
- [ ] Are my instructions consistent? (no toxicity)

## Key Quote

> "A focused agent is a performant agent. Context problems are the #1 cause of agent performance issues."

---

**Cross-References:**

- @rd-framework.md - Reduce and Delegate strategies
- @context-layers.md - Understanding context composition
- @context-priming-patterns.md - Loading fresh, relevant context
