# Workflow SOP: TAC Plugin Lesson Processing

**Version:** 2.0
**Last Updated:** 2025-12-04

This SOP defines the 6-phase workflow for planning and implementing each TAC lesson as Claude Code ecosystem components.

---

## Overview

Each lesson is processed through 6 phases:

1. **Input Gathering** - Read all source materials
2. **Repo Exploration** - Extract patterns from companion repos
3. **Docs Validation** - Validate against official Claude Code docs (MANDATORY)
4. **Plan Creation** - Write lesson implementation plan
5. **Implementation** - Build the components
6. **Tracker Update** - Record progress

---

## Phase 1: Input Gathering

**Goal**: Collect and read all source materials for the lesson

| Step | Action | Source |
| ------ | -------- | -------- |
| 1.1 | Read lesson summary | `lessons/lesson-NNN-*/lesson.md` |
| 1.2 | Read full transcript (authoritative) | `lessons/lesson-NNN-*/captions.txt` |
| 1.3 | Review external links | `lessons/lesson-NNN-*/links.md` |
| 1.4 | Note companion repo | `lessons/lesson-NNN-*/repos.md` |
| 1.5 | Review any images/cards | `lessons/lesson-NNN-*/images/` |
| 1.6 | Read existing analysis | `analysis/lesson-NNN-analysis.md` |
| 1.7 | Check cross-lesson components | `analysis/CONSOLIDATION.md` |
| 1.8 | Check validation findings | `analysis/DOCUMENTATION_AUDIT.md` |

**Quality Gate**: All 8 sources reviewed before proceeding.

---

## Phase 2: Companion Repo Exploration

**Goal**: Extract patterns, code examples, and implementation details from disler repos

| Step | Action | Notes |
| ------ | -------- | ------- |
| 2.1 | Explore repo structure | `D:\repos\gh\disler\{repo-name}\` |
| 2.2 | Identify CLAUDE.md patterns | Memory file examples |
| 2.3 | Find ADW/workflow examples | Agent-Driven Workflow patterns |
| 2.4 | Extract SDK usage patterns | Note Python patterns for TS conversion |
| 2.5 | Document hooks/configs | Hook implementations, settings |
| 2.6 | Note prompt templates | Slash commands, system prompts |

**Quality Gate**: Key patterns documented for TypeScript transformation.

---

## Phase 3: Official Documentation Validation

**Goal**: Validate all proposed components against canonical Claude Code docs

### MANDATORY: Invoke `docs-management` skill

Before finalizing ANY component design, you MUST invoke the `docs-management` skill to validate against official Claude Code documentation.

**This is non-negotiable.** Every component must be validated against official canonical docs before implementation.

### How to Invoke docs-management

Use the Skill tool to invoke `claude-ecosystem:docs-management`, then run search queries:

```bash
# For skills validation
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search skill frontmatter allowed-tools

# For agents validation
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search subagent tools array model

# For commands validation
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search slash command frontmatter description

# For hooks validation
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search hook events PreToolUse matcher
```

**Document your validation**: In the lesson plan's Validation Criteria section, record:
- Which `docs-management` queries were invoked
- What official documentation was retrieved
- Any discrepancies found and how they were resolved

### Official Documentation Key Findings

Based on official Claude Code documentation (code.claude.com), here are the authoritative specifications:

#### Skills (from official docs)

- **Frontmatter fields**: `name` (max 64 chars, lowercase + hyphens), `description` (max 1024 chars)
- **`allowed-tools`**: Comma-separated string (NOT array): `allowed-tools: Read, Grep, Glob`
- **File**: `SKILL.md` in a directory under `skills/`
- **Invocation**: Model-invoked (Claude decides when to use based on description)

#### Agents/Subagents (from official docs)

- **Frontmatter fields**: `name`, `description` (required), `tools` (optional), `model` (optional)
- **`tools`**: Comma-separated list OR array format (both work per official docs): `tools: Read, Grep, Glob`
- **`model`**: Valid values are `sonnet`, `opus`, `haiku`, `inherit` (default: configured subagent model, usually `sonnet`)
- **Constraint**: Subagents CANNOT spawn other subagents

#### Commands (from official docs)

- **Location**: `.claude/commands/` (project) or `~/.claude/commands/` (user)
- **Frontmatter**: `description`, `allowed-tools`, `argument-hint`, `model`, `disable-model-invocation`
- **Arguments**: `$ARGUMENTS` (all args), `$1`, `$2`, etc. (positional)
- **File references**: Use `@` prefix for file inclusion

### Component Validation Checks

| Component Type | Validation Checks |
| ---------------- | ------------------- |
| **Skills** | Frontmatter syntax, `allowed-tools` (comma-separated), noun-phrase naming, max 64 char name, max 1024 char description |
| **Agents** | `tools` array, model selection (`sonnet`/`opus`/`haiku`/`inherit`), NO nested spawning, no built-in overlap |
| **Commands** | kebab-case naming, argument patterns (`$ARGUMENTS`, `$1`, `$2`) |
| **Memory** | Import syntax (`@path/to/file.md`), hierarchy patterns, progressive disclosure |
| **Hooks** | Event types (see below), matcher patterns, when to block vs log |
| **Output Styles** | Frontmatter structure, `keep-coding-instructions` |
| **MCP** | Server configuration, tool naming, OAuth patterns |
| **SDK** | TypeScript patterns, `ClaudeAgentOptions` (not `ClaudeCodeOptions`) |

### Built-in Agent Evaluation (REQUIRED for Agent Components)

Before proposing a new agent, check against existing claude-ecosystem built-in agents:

| Built-in Agent | Purpose | If Your Agent Does This... |
| ---------------- | --------- | --------------------------- |
| `Explore` | Codebase exploration | Use Explore instead, or create specialized skill |
| `Plan` | Implementation planning | Use Plan instead, or create specialized skill |
| `code-reviewer` | Code quality review | Extend via skill, don't duplicate |
| `codebase-analyst` | Deep analysis | Extend via skill, don't duplicate |
| `debugger` | Root cause analysis | Extend via skill, don't duplicate |
| `history-reviewer` | Git history | Extend via skill, don't duplicate |

**Resolution options when overlap exists**:

1. Use the built-in agent directly
2. Create a skill that the built-in can invoke
3. If new agent truly needed, document clear differentiation

### Hook Event Types Reference

Valid hook events for Claude Code hooks:

| Event | When Triggered | Common Use Cases |
| ------- | --------------- | ------------------ |
| `PreToolUse` | Before any tool executes | Block dangerous commands, validate inputs |
| `PostToolUse` | After tool completes | Log results, trigger follow-up actions |
| `UserPromptSubmit` | When user submits prompt | Inject context, validate prompts |
| `Notification` | On notifications | Alert on specific events |
| `Stop` | When agent stops | Cleanup, final logging |

**Matcher patterns**: Tool name strings or regex patterns to filter which tools trigger the hook.

### MCP Servers for External Docs

| Server | Use For |
| -------- | --------- |
| `docs-management` skill | ALL Claude Code ecosystem topics (MANDATORY) |
| `context7` | TypeScript SDK, npm packages, library docs |
| `ref` | GitHub repo docs, API references |
| `microsoft-learn` | TypeScript/Node.js patterns |
| `perplexity` | Latest patterns, debugging, alternatives |

**Quality Gate**: All components validated against official docs.

---

## Phase 4: Create Lesson Implementation Plan

**Goal**: Document what to build and how

Create `implementation-plan/lesson-plans/lesson-NNN-plan.md` using the template at `templates/lesson-plan-template.md`.

**Plan Must Include**:

- Lesson summary (core tactic, key frameworks)
- Components to implement (skills, agents, commands, memory, other)
- Implementation order with dependencies
- Validation criteria
- Python-to-TypeScript transformations
- Notes on blockers/decisions

**Quality Gate**: Plan is complete and actionable.

---

## Phase 5: Implementation

**Goal**: Build components according to the plan

| Step | Action |
| ------ | -------- |
| 5.1 | Create skills first (foundational) |
| 5.2 | Create agents that use those skills |
| 5.3 | Create commands that invoke agents/skills |
| 5.4 | Create memory files that support all three |
| 5.5 | Create hooks, output styles, MCP configs as needed |
| 5.6 | Update `plugin.json` as components are added |
| 5.7 | Validate each component works |

### Component Creation Order

```text
Skills (foundational)
    ↓
Agents (use skills)
    ↓
Commands (invoke agents/skills)
    ↓
Memory Files (support all)
    ↓
Hooks, Output Styles, MCP (as needed)
    ↓
plugin.json update
```

### plugin.json Update Guidance

Update `plugin.json` incrementally as components are added. The manifest structure:

```json
{
  "name": "tactical-agentic-coding",
  "version": "0.1.0",
  "description": "...",
  "skills": ["skill-name"],
  "agents": ["agent-name"],
  "commands": ["command-name"],
  "hooks": ["hook-name"]
}
```markdown

**When to update**:

- After each skill is created and validated
- After each agent is created and validated
- After each command is created and validated
- After each hook is created and validated

**Array ordering**: Add components in order of creation (foundational first).

**Validation**: After updating, verify the plugin loads correctly:

```bash
claude /plugin list  # Should show tactical-agentic-coding
claude /plugin info tactical-agentic-coding  # Should list components
```yaml

**Quality Gate**: All components created and validated.

---

## Phase 6: Update Master Tracker

**Goal**: Record progress for cross-session continuity

Update `MASTER-TRACKER.md` with:

- [x] mark lesson Plan status
- Update component counts (Skills, Agents, Cmds, Memory, Other)
- Note any outstanding issues/blockers
- Update Next Actions

**Quality Gate**: Tracker accurately reflects current state.

---

## Quality Gates Summary

| Phase | Gate |
| ------- | ------ |
| 1 | All 8 input sources reviewed |
| 2 | Repo patterns documented |
| 3 | docs-management skill invoked, all components validated |
| 4 | Plan written with all required sections |
| 5 | All components created and validated |
| 6 | Tracker updated |

---

## Python-to-TypeScript Reference

Common transformations from course Python to Claude Agent SDK TypeScript:

| Python Pattern | TypeScript Equivalent |
| ---------------- | ---------------------- |
| `@tool` decorator | `tool()` with Zod schemas |
| `ClaudeSDKClient` | `query()` async generator |
| `ClaudeCodeOptions` | `ClaudeAgentOptions` |
| `snake_case` options | `camelCase` options |
| `async with client:` | `for await (const msg of query())` |
| `setting_sources=["project"]` | `settingSources: ["project"]` |

---

## Model Selection Guide

**Opus 4.5 is the new workhorse** for complex tasks. Use the following guidance for TAC component model selection:

### Agent Model Selection

| Agent Type | Recommended Model | Rationale |
| ------------ | ------------------- | ----------- |
| **Orchestration agents** | `opus` | Complex multi-step coordination, master planning |
| **Planning agents** | `opus` | Architecture decisions, implementation strategy |
| **Implementation agents** | `sonnet` | Balanced quality and speed for code generation |
| **Review agents** | `sonnet` | Thorough analysis with reasonable latency |
| **Classification agents** | `haiku` | Fast, cost-efficient for simple decisions |
| **Test runners** | `haiku` | Simple execution, minimal reasoning needed |
| **Scout/exploration agents** | `haiku` | Fast codebase exploration |

### TAC Agents to Use Opus

The following TAC agents should use `opus` model due to their complexity:

| Agent | Reason for Opus |
| ------- | ----------------- |
| `plan-generator` | Generates comprehensive implementation plans |
| `plan-implementer` | Executes complex plans with validation |
| `sdlc-planner` | Full SDLC planning requiring deep reasoning |
| `orchestration-planner` | Multi-phase coordination design |
| `workflow-coordinator` | Complex workflow management |
| `workflow-designer` | Architectural workflow design |

### When to Use Each Model

```
opus    → Orchestration, delegation, complex planning, master planning
sonnet  → Implementation, review, moderate complexity
haiku   → Fast tasks, classification, simple analysis, exploration
inherit → When subagent should match parent conversation model
```

### Model Selection Decision Tree

```
Is the agent an orchestrator or planner?
├── YES → Use opus
└── NO
    ├── Does it require complex reasoning or multi-step analysis?
    │   ├── YES → Use sonnet
    │   └── NO
    │       ├── Is it classification, exploration, or simple execution?
    │       │   ├── YES → Use haiku
    │       │   └── NO → Default to sonnet
```

---

## Key Principles

1. **docs-management MANDATORY**: For ALL Claude Code topics
2. **TypeScript SDK**: Transform all Python patterns
3. **Naming Conventions**: noun-phrase (skills), verb-phrase (commands), kebab-case
4. **No Duplicates**: Check existing plugins before creating
5. **Single Source of Truth**: Link, don't duplicate
6. **Actionable Components**: Provide real value, not just documentation
7. **Model Selection**: Opus for orchestration/planning, Sonnet for implementation, Haiku for fast tasks

---

## Troubleshooting

### Skill won't load

- Check `allowed-tools` is comma-separated (not array)
- Verify name is max 64 chars, lowercase + hyphens only
- Ensure no "anthropic" or "claude" in name

### Agent won't spawn

- Verify `tools` is an array (not comma-separated like skills)
- Check model is valid (`sonnet`, `opus`, `haiku`, `inherit`)
- Remember: subagents CANNOT spawn other subagents

### Command not recognized

- Use kebab-case (not underscores)
- Check file is in `commands/` folder
- Verify frontmatter if using YAML

### SDK pattern fails

- Use `ClaudeAgentOptions` (not `ClaudeCodeOptions`)
- Check TypeScript vs Python syntax differences
- Verify import paths for TypeScript SDK

---

## Component File Locations

When implementing components, place them in these locations:

| Component Type | Location | File Pattern |
| ---------------- | ---------- | -------------- |
| **Skills** | `skills/{skill-name}/` | `SKILL.md` + optional `scripts/`, `references/` |
| **Agents** | `agents/` | `{agent-name}.md` |
| **Commands** | `commands/` | `{command-name}.md` |
| **Memory Files** | `memory/` | `{file-name}.md` |
| **Hooks** | `hooks/` | `{hook-name}.js` or `{hook-name}.ts` |
| **Output Styles** | `output-styles/` | `{style-name}.md` |
| **MCP Configs** | `.claude/settings.json` | In `mcpServers` section |

### Skill Directory Structure

```

skills/{skill-name}/
  SKILL.md           # Main skill file with YAML frontmatter
  scripts/           # Optional: executable scripts
    core/            # Core functionality
    utils/           # Helpers
  references/        # Optional: detailed documentation
  assets/            # Optional: templates, images

```yaml

---

## Handling Zero-Component Lessons

Some lessons (like Lesson 001) are foundational philosophy with no actionable skills/agents/commands.

**This is valid.** When a lesson has no components of a certain type:

1. Document in the plan with rationale (e.g., "Lesson 1 is foundational philosophy")
2. Use `*None*` in component tables with explanation
3. Still create memory files if the lesson introduces concepts worth encoding
4. Update MASTER-TRACKER with `0/0` (implemented/expected) for that component type

**Pattern**: Early lessons (001-002) tend to be conceptual. Skills/agents/commands appear from lesson 003 onward.

---

## Cross-Lesson Deduplication

Before creating a component, check if a similar one exists from another lesson.

### Deduplication Check (Add to Phase 3 or 4)

1. **Search CONSOLIDATION.md** for similar component names
2. **Search existing lesson plans** for overlapping functionality
3. **If duplicate found**:
   - Merge into single component with broader scope
   - Note the merge in both lesson plans
   - Update component to reference both lessons as sources

### Common Overlap Patterns

| Pattern | Resolution |
| --------- | ------------ |
| Multiple planning skills | Consolidate into single `plan-generation` skill |
| Similar testing agents | Use parameters to differentiate (unit vs e2e) |
| Overlapping memory files | Merge and use imports for lesson-specific content |

---

## SDK-Only Patterns (Lessons 11-12)

Some patterns from the course **cannot be implemented as Claude Code subagents** due to architectural constraints.

### The Constraint

> "Subagents cannot spawn other subagents" - Official Claude Code docs

### Affected Components

| Component | Why SDK-Only | Implementation Path |
| ----------- | -------------- | --------------------- |
| `orchestrator-agent` | Needs to spawn other agents | Claude Agent SDK + MCP tools |
| `fleet-manager` | Manages agent lifecycle | SDK + database backend |
| Multi-agent orchestration | Nested agent spawning | SDK pattern per Lesson 12 |

### What This Means for the Plugin

1. **Document as SDK patterns** - Not Claude Code subagents
2. **Provide reference implementations** - Point to Lesson 12 repo
3. **Create guidance skills** - Help users build SDK solutions
4. **Memory files for concepts** - Encode orchestration patterns for reference

### SDK Implementation Path (TypeScript)

```typescript
// This runs OUTSIDE Claude Code as a standalone service
import { query, ClaudeAgentOptions, tool } from "@anthropic-ai/claude-agent-sdk";

const createAgent = tool({
  name: "create_agent",
  description: "Create a specialized agent",
  schema: z.object({ template: z.string(), name: z.string() }),
  handler: async ({ template, name }) => {
    // Create agent in database, return ID
  }
});

const options: ClaudeAgentOptions = {
  model: "sonnet",
  mcpServers: { orchestrator: createSdkMcpServer([createAgent, commandAgent, deleteAgent]) }
};
```yaml

---

## Parallelization Guidance

For lessons with many components, consider parallelization:

### When to Parallelize

| Scenario | Approach |
| ---------- | ---------- |
| 1-3 components | Sequential (simple) |
| 4-6 components | Consider parallel if independent |
| 7+ components | Parallelize independent items |

### What Can Run in Parallel

- **Skills** that don't depend on each other
- **Memory files** (always independent)
- **Commands** that invoke different skills/agents

### What Must Be Sequential

- **Agent** that uses a **skill** (skill first)
- **Command** that invokes an **agent** (agent first)
- Components with explicit dependencies

### Parallel Execution Pattern

```

Phase 5.1: Skills (can parallelize if independent)
  ├── skill-a (parallel)
  ├── skill-b (parallel)
  └── skill-c (parallel)

Phase 5.2: Agents (after skills, can parallelize)
  ├── agent-x uses skill-a (parallel)
  └── agent-y uses skill-b (parallel)

Phase 5.3: Commands (after agents, can parallelize)
  └── /command-1 invokes agent-x

```text
