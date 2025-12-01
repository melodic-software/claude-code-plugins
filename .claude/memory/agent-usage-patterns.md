# Agent Usage Patterns

This document consolidates guidance on when and how to use Task agents effectively, including parallelization strategies, model selection, and best practices.

## When to Use Task Agents

**Offload work to agents when:**

- Multi-step research tasks (exploring codebase, gathering information)
- Complex codebase exploration (finding patterns, understanding architecture)
- Parallel investigations (multiple independent search tasks)
- Time-consuming readonly operations (audit trails, comprehensive searches)
- Specialized tasks matching agent descriptions (Explore, Plan, etc.)

**Do NOT use agents when:**

- Simple file reads (use Read tool directly)
- Single grep/glob operations (use Grep/Glob tools directly)
- Straightforward edits (use Edit/Write tools directly)
- Tasks requiring back-and-forth clarification (agents can't ask questions)

**Mental Model:**

```text
Simple Task (1-3 steps)  -> Direct tools (Read, Grep, Edit)
Complex Task (4+ steps)  -> Consider agent
Parallel Tasks           -> Multiple agents in single message
Research/Exploration     -> Explore agent
```

## Parallelization Strategy (90% Speedup)

**Source:** Anthropic multi-agent research

**Pattern:** Run 3-5 independent subagents simultaneously instead of sequentially.

### When to Parallelize

**Run agents in parallel when:**

- Tasks are independent (no dependencies between them)
- Results don't inform each other
- Can be executed concurrently for speed

**Run agents sequentially when:**

- One task depends on another's output
- Results need to be combined or compared
- Order matters for decision-making

### Parallelization Check (MANDATORY)

Before executing ANY plan with multiple tasks, verify parallelization opportunities:

- [ ] **How many independent tasks** are in this plan?
- [ ] **Can any tasks run concurrently?** (If yes -> MUST parallelize)
- [ ] **Am I about to do 2+ similar operations?** (If yes -> delegate each to a subagent)
- [ ] **Is this research/exploration?** (If yes -> use Explore subagent to preserve main context)
- [ ] **Sequential execution justified?** (Document why if choosing sequential over parallel)

**Recognition patterns that MUST trigger parallelization:**

- "Create N files/commands/components" -> N parallel subagents (max 5 concurrent)
- "Update across N platforms" -> 1 subagent per platform
- "Analyze/audit/review multiple items" -> 1 subagent per item
- "Research topic X" -> Explore subagent (preserves main context)
- "Compare A vs B vs C" -> 1 subagent per item being compared

**Failure to parallelize when possible is a violation of operational rules.**

### How to Parallelize

Send a **single message** with **multiple Task tool calls**:

```markdown
I need to analyze this codebase comprehensively.

[Task 1: Security scan with Explore agent]
[Task 2: Performance analysis with Explore agent]
[Task 3: Style check with Explore agent]
[Task 4: Documentation completeness with Explore agent]

All executed in parallel, results aggregated when complete.
```

**Key:** Must be single message with multiple tool invocations for true parallelization.

### Example: Sequential vs Parallel

**Sequential (Slow):**

```text
1. Security scan -> wait (2 minutes)
2. Performance analysis -> wait (2 minutes)
3. Style check -> wait (2 minutes)
Total: 6 minutes
```

**Parallel (Fast):**

```text
Single message with 3 Task tool calls:
1. Security scan subagent
2. Performance analysis subagent
3. Style check subagent

Total: ~2 minutes (90% speedup)
```

## Model Selection (2-3x Speedup)

**Use Haiku for:**

- Simple analysis tasks
- Straightforward research
- File searches and exploration
- Quick validation checks
- Repetitive operations

**Use Sonnet for:**

- Complex reasoning
- Multi-step planning
- Code generation
- Decision-making with trade-offs

**Use Opus for:**

- Highest complexity tasks
- Critical decision-making
- Multi-stage reasoning

**Example:**

```text
Task: Find all Git configuration files in the repo

Sonnet: Slower, more expensive, overkill for simple search
Haiku: 2-3x faster, 4x cheaper, perfectly capable for this task
```

**How to specify model:**

```markdown
Use Task tool with model parameter:
- model: "haiku" for simple tasks
- model: "sonnet" for standard tasks
- model: "opus" for complex reasoning
```

## Subagent Resumption

**Pattern:** Reuse existing subagent context instead of creating new agents.

**Resume existing agent:**

```text
Task(resume="agent_abc123")
- Reuses previous context
- Continues from where it left off
- No re-initialization overhead
```

**Create new agent:**

```text
Task(new agent)
- Full initialization
- Repeats context loading
- Slower startup
```

**Use resumption when:**

- Iterating on previous analysis
- Following up with additional questions
- Refining previous results

## Agent Communication Pattern

**Use temporary files for agent handoffs:**

When one agent's output is needed by another agent (or the main conversation), store it in `.claude/temp/`:

```markdown
1. Agent A: Explores codebase, writes findings to `.claude/temp/2025-01-09_143022-explore-git-patterns.md`
2. Agent B: Reads that file, creates plan, writes to `.claude/temp/2025-01-09_150000-plan-git-refactor.md`
3. Main conversation: Reads plan file, discusses with user, executes
```

**Why this works:**

- Agents can't communicate directly
- File-based handoffs preserve full context
- Timestamped files create audit trail
- Main conversation can review agent work before proceeding

## Agent Prompt Best Practices

**Comprehensive prompts are critical:**

Agents cannot ask follow-up questions. Your prompt must include:

- Full context of the task
- Specific deliverables expected
- Relevant background information
- Constraints or requirements
- Format for the output (markdown, specific structure, etc.)

**Good Prompt Example:**

```markdown
I need you to explore the codebase to find all Git-related configuration patterns.

Context:
- This is a plugin repository with multiple ecosystem plugins
- We're auditing how Git operations are handled across plugins
- We need to ensure consistency and completeness

Specific tasks:
1. Find all files containing "git" in the filename
2. Search for Git configuration examples (.gitconfig references)
3. Note any plugin-specific differences in Git handling
4. Identify any missing verification steps

Deliverable:
Write findings to `.claude/temp/2025-01-09_143022-explore-git-config.md` with:
- List of all Git-related files found (grouped by plugin)
- Summary of configuration patterns (what's consistent, what varies)
- Gaps or inconsistencies noted
- Recommendations for standardization

This is READONLY research - do not make any edits.
```

**Bad Prompt Example:**

```markdown
Look at Git stuff and let me know what you find.
```

This lacks context, specific tasks, deliverables, and constraints. The agent won't know what to focus on.

## Context Gatekeeping vs Full Context Clones

Understanding the trade-offs between custom specialized subagents and general-purpose Task() clones.

### The Custom Subagent Trade-off

Custom subagents can create two problems:

1. **Context Gatekeeping**: A specialized "PythonTests" subagent hides all testing context from the main agent. The main agent can no longer reason holistically about changes - it's forced to invoke the subagent just to know how to validate its own code.

2. **Forced Human Workflows**: Custom subagents encode rigid, human-defined workflows. The agent can no longer adapt its approach dynamically - you're dictating exactly how it must delegate, which is the very problem you want the agent to solve.

### Preferred: Task() with Full Context

Instead of specialized subagents:

1. Put key context in CLAUDE.md (accessible to all agents)
2. Let main agent use Task() to spawn clones of itself
3. Clones inherit full CLAUDE.md context
4. Main agent decides when/how to delegate dynamically

**Benefits:**

- Full context available to all agents
- Dynamic delegation based on task needs
- No artificial boundaries or gatekeeping
- Agent manages its own orchestration

### When Custom Subagents ARE Appropriate

Custom subagents make sense when:

- **Truly specialized domain** - Security scanning, specific toolchains
- **Well-defined narrow scope** - Single responsibility, clear boundaries
- **Context isolation is a FEATURE** - You want to prevent cross-contamination
- **Different tool access needed** - Subagent needs different permissions

### Architecture Comparison

| Pattern           | Pros                           | Cons                              |
| ----------------- | ------------------------------ | --------------------------------- |
| Custom Subagents  | Clear responsibilities         | Gatekeeps context, rigid workflow |
| Task() Clones     | Full context, flexible         | Less specialization               |
| Hybrid            | Best of both                   | More complex to manage            |

### Practical Guidance

**Start with Task() clones.** Only create custom subagents when you have a clear reason for context isolation or specialization.

**Signs you need a custom subagent:**

- Repeated patterns that benefit from specialized prompting
- Security boundaries (agent shouldn't see certain data)
- Different model requirements (e.g., vision-capable agent)

**Signs Task() clones are better:**

- Agent needs full codebase understanding
- Tasks vary significantly in nature
- Flexibility is more important than specialization

## Default Behavior: Consider Agents, Don't Over-Engineer

**It Depends:**

- Use agents when they add value (speed, thoroughness, parallelization)
- Use direct tools when agents would be overhead
- Bias toward simplicity for straightforward tasks
- Bias toward agents for complex, multi-step work

## Repository Subagent Conventions

This section documents the established patterns for custom subagents in `.claude/agents/`.

### YAML Frontmatter Reference

Official Claude Code subagent specification:

| Field | Required | Description |
| ----- | -------- | ----------- |
| `name` | Yes | Unique identifier using lowercase letters and hyphens |
| `description` | Yes | Natural language description of when to invoke (use "PROACTIVELY" for auto-delegation) |
| `tools` | No | Comma-separated list of tools. If omitted, inherits all tools |
| `model` | No | Model alias: `sonnet`, `opus`, `haiku`, or `inherit`. If omitted, uses default |
| `skills` | No | Comma-separated list of skills to auto-load |
| `permissionMode` | No | Valid values: `default`, `acceptEdits`, `bypassPermissions`, `plan`, `ignore` |
| `color` | No | Visual organization (not in official spec, but supported) |

### Model Selection Rationale

**Repository Decision:** All custom subagents use `model: opus`

**Rationale:**

- All agents perform complex analysis, research, or generation tasks
- Consistency simplifies mental model and reduces configuration errors
- Opus provides highest capability for code review, debugging, test generation
- Cost/speed trade-off acceptable for quality-critical tasks

**When to consider Haiku:**

- Simple coordination tasks (primarily delegating to skills)
- Fast file searches (built-in Explore uses Haiku)
- High-volume, low-complexity operations

### Color Scheme Convention

Visual organization using `color` field:

| Color | Agent Category | Examples |
| ----- | -------------- | -------- |
| **blue** | Code analysis/generation | codebase-analyst, test-generator, debugger, code-reviewer |
| **green** | Research/retrieval | web-research, platform-docs-researcher, mcp-research, git |
| **purple** | Validation/meta-level | skill-auditor, docs-validator |

### Single Source of Truth Pattern

Agents that delegate to skills use explicit CRITICAL sections:

```markdown
## CRITICAL: Single Source of Truth Pattern

The `{skill-name}` skill is the AUTHORITATIVE source for:
- [Criteria/checklists]
- [Definitions]
- [Reference loading]

Do NOT hardcode criteria - invoke and follow the skill's guidance.
```

**Agents using this pattern:**

- `skill-auditor` -> `skills-meta` skill
- `code-reviewer` -> `code-reviewing` skill

### Tool Restriction Patterns

**Read-Only Agents (analysis, review, validation):**

```yaml
tools: Read, Glob, Grep
```

**Modification Agents (fix, generate):**

```yaml
tools: Read, Write, Edit, Glob, Grep, Bash
```

**Research Agents (web, MCP):**

```yaml
tools: WebFetch, WebSearch, mcp__*
```

**Principle:** Grant only tools necessary for the agent's purpose.

### File Organization

- **Location:** All agents in `.claude/agents/` (flat structure)
- **Naming:** `kebab-case.md` matching the `name` field
- **Priority:** Project agents (`.claude/agents/`) override user agents (`~/.claude/agents/`)

## Quick Reference Checklist

Before starting any significant task, ask:

- [ ] Can this be parallelized? (Use 3-5 agents)
- [ ] Is this a simple task? (Use Haiku model)
- [ ] Am I loading too much context? (Use focused queries)
- [ ] Can I reuse an existing agent? (Use resumption)
- [ ] Do I need exhaustive results? (Use head_limit, pagination)
- [ ] Is this better delegated to a subagent? (Offload to Task)

**Remember:** Claude Code isn't slower - it's differently optimized. Use parallelization and you'll match or exceed Cursor's performance.

---

**Last Updated:** 2025-11-30
