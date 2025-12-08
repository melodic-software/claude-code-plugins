# Lesson 009: Elite Context Engineering - Implementation Plan

## Lesson Overview

**Title:** Elite Context Engineering
**Core Tactic:** Master Context Engineering - The R&D Framework
**Key Insight:** "A focused agent is a performant agent. The context window is your agent's most precious resource."

## Source Materials Validated

- [x] lesson-009-analysis.md - Comprehensive analysis with R&D framework, context layers, 12 techniques
- [x] lesson.md - Core concepts: R&D Framework, Context Sweet Spot, Four Levels of Context Engineering
- [x] elite-context-engineering repo - Explored commands, agents, hooks, output styles, patterns

## Components to Create

### Memory Files (4 files)

| File | Purpose | Source |
| ------ | --------- | -------- |
| `rd-framework.md` | R&D (Reduce & Delegate) framework for context management | Lesson 009 core concept |
| `context-layers.md` | Seven layers of context: System Prompt, User Prompt, History, Tools, Results, Files, Memory | Analysis context layer priorities |
| `context-rot-vs-pollution.md` | Distinguish context rot (stale) from pollution (irrelevant) from toxic (conflicting) | Analysis anti-patterns |
| `context-priming-patterns.md` | Dynamic priming commands vs static memory files | Repo /prime, /prime_cc patterns |

### Skills (4 skills)

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `context-audit` | Audit current context composition and identify bloat | Read, Grep, Glob |
| `reduce-delegate-framework` | Apply R&D framework to optimize prompts and context | Read, Grep, Glob |
| `context-hierarchy-design` | Design memory hierarchy with progressive loading | Read, Grep, Glob |
| `agent-expert-creation` | Create specialized agent experts with pre-loaded domain knowledge | Read, Grep, Glob |

### Commands (3 commands)

| Command | Purpose | Arguments |
| --------- | --------- | ----------- |
| `context-status` | Show context window state and consumption | None |
| `context-prime` | Load task-specific context dynamically | `$ARGUMENTS` - context type (bug, feature, review) |
| `load-context-bundle` | Reload previous session context from bundle file | `$1` - bundle file path |

### Agents (2 agents)

| Agent | Purpose | Tools | Model |
| ------- | --------- | ------- | ------- |
| `context-analyzer` | Analyze context composition and identify reduction opportunities | Read, Grep, Glob | haiku |
| `context-optimizer` | Suggest context reductions and delegation strategies | Read, Grep, Glob | sonnet |

## Component Specifications

### Memory File: rd-framework.md

**Content Outline:**

- The R&D Framework: Only Two Strategies
  - **R - Reduce**: Remove unnecessary context, strip noise, avoid bloat
  - **D - Delegate**: Offload to sub-agents, use fresh instances
- When to Reduce:
  - Verbose tool outputs consuming tokens
  - Long conversation history accumulation
  - Irrelevant files loaded "just in case"
- When to Delegate:
  - Complex subtasks requiring different context
  - Research tasks that would pollute primary context
  - Parallel work that doesn't need shared state
- Context Sweet Spot: Range where agent performs optimally
- Measuring Success: Signal-to-noise ratio, fresh instance rate, delegation rate

### Memory File: context-layers.md

**Content Outline:**

- Seven Layers of Context (Priority Order):
  1. System Prompt (law of the agent)
  2. User Prompt (current task)
  3. Tool Definitions (capabilities)
  4. Tool Results (working memory)
  5. Conversation History (compressed over time)
  6. Files Read (reference material)
  7. Memory Files (CLAUDE.md imports)
- Each Layer's Impact:
  - System prompt: Highest priority, shapes all reasoning
  - Tool results: Consume most tokens during execution
  - Conversation history: Compresses over time
- Optimization Per Layer:
  - Keep system prompts focused
  - Control output verbosity
  - Use fresh instances to reset history

### Memory File: context-rot-vs-pollution.md

**Content Outline:**

- Three Context Problems:

  | Issue | Description | Symptoms | Solution |
  | ------- | ------------- | ---------- | ---------- |
  | Context Rot | Old, stale context | Outdated info guides decisions | Fresh agent instances |
  | Context Pollution | Irrelevant context added | Diluted focus, wasted tokens | R&D framework |
  | Toxic Context | Conflicting/confusing context | Contradictory behavior | Clear prompts, isolation |

- Detection Patterns:
  - Rot: Agent references outdated patterns or removed code
  - Pollution: Agent struggles to focus on current task
  - Toxic: Agent produces inconsistent or contradictory outputs
- Prevention Strategies:
  - Start fresh instances for new task types
  - Use delegation for tangential work
  - Keep prompts focused and non-contradictory

### Memory File: context-priming-patterns.md

**Content Outline:**

- Static Memory vs Dynamic Priming:

  | Approach | Pros | Cons |
  | ---------- | ------ | ------ |
  | CLAUDE.md | Always available | Grows over time, becomes bloated |
  | /prime commands | Task-specific, controllable | Requires explicit invocation |

- Priming Command Patterns:
  - `/prime` - Base codebase understanding (git ls-files, README)
  - `/prime_cc` - Claude Code specific context
  - `/prime_bug` - Bug-fixing context
  - `/prime_feature` - Feature development context
- Building Priming Commands:
  - Run: Execute discovery commands
  - Read: Load specific files
  - Report: Summarize understanding
- The Guiding Question: "Does every piece of this context serve the current task?"

### Skill: context-audit

**Purpose:** Audit current context composition and identify optimization opportunities.

**Workflow:**

1. Check CLAUDE.md size and imports
2. Scan for MCP server configurations
3. Review .claude/commands/ count and complexity
4. Check hooks for context-consuming patterns
5. Score context efficiency
6. Report recommendations

**Output:** Structured audit report with scores and action items.

### Skill: reduce-delegate-framework

**Purpose:** Apply R&D framework to optimize prompts and workflows.

**Workflow:**

1. Analyze provided prompt or workflow
2. Identify reduction opportunities (verbose sections, unused context)
3. Identify delegation opportunities (subtasks, research, parallel work)
4. Suggest specific transformations
5. Provide before/after comparison

**Output:** Optimization recommendations with examples.

### Skill: context-hierarchy-design

**Purpose:** Design memory hierarchy with progressive loading.

**Workflow:**

1. Analyze project structure and task types
2. Identify always-needed context (CLAUDE.md)
3. Identify task-type context (priming commands)
4. Identify on-demand context (file reads)
5. Design import hierarchy
6. Create priming command structure

**Output:** Memory hierarchy design document.

### Skill: agent-expert-creation

**Purpose:** Create specialized agent experts with pre-loaded domain knowledge.

**Workflow:**

1. Define domain area (frontend, backend, testing, security)
2. Identify required expertise context
3. Design focused system prompt
4. Select appropriate tools (minimal set)
5. Create plan-build-improve command triplet
6. Generate agent definition

**Output:** Agent expert definition with commands.

### Command: context-status

**Purpose:** Show context window state and give awareness of consumption.

**Implementation:**

- Reference `/context` built-in command
- Provide interpretation of context state
- Highlight warning signs (approaching limits, bloat indicators)

### Command: context-prime

**Purpose:** Load task-specific context dynamically.

**Implementation:**

- Accept context type: bug, feature, review, chore, research
- Execute appropriate discovery commands
- Load relevant files
- Report loaded context summary

### Command: load-context-bundle

**Purpose:** Reload previous session context from bundle file.

**Implementation:**

- Read JSONL bundle file
- Deduplicate file entries intelligently
- Read files with optimal parameters
- Report context restoration summary

### Agent: context-analyzer

**Purpose:** Analyze context composition and identify reduction opportunities.

**Configuration:**

- Model: haiku (fast analysis)
- Tools: Read, Grep, Glob (read-only)
- Focus: Scanning and measuring

**Output:** JSON report with context breakdown and scores.

### Agent: context-optimizer

**Purpose:** Suggest context reductions and delegation strategies.

**Configuration:**

- Model: sonnet (reasoning for optimization)
- Tools: Read, Grep, Glob (read-only)
- Focus: Recommendations and transformations

**Output:** Optimization plan with specific suggestions.

## Implementation Order

1. Create memory files (foundational knowledge)
   - rd-framework.md
   - context-layers.md
   - context-rot-vs-pollution.md
   - context-priming-patterns.md

2. Create skills (workflows for optimization)
   - context-audit
   - reduce-delegate-framework
   - context-hierarchy-design
   - agent-expert-creation

3. Create commands (user-facing operations)
   - context-status
   - context-prime
   - load-context-bundle

4. Create agents (specialized workers)
   - context-analyzer
   - context-optimizer

5. Update plugin.json

## Validation Criteria

- [ ] Memory files explain R&D framework clearly
- [ ] Skills provide actionable optimization workflows
- [ ] Commands integrate with Claude Code built-in features
- [ ] Agents follow one-agent-one-purpose principle
- [ ] All naming follows kebab-case convention
- [ ] Skills use `allowed-tools` as comma-separated string
- [ ] Agents use `tools` as array
- [ ] No duplicates with existing plugin components

## Cross-References

- **Lesson 002**: Context as #1 leverage point
- **Lesson 006**: One agent, one purpose (focused context)
- **Lesson 007**: Fresh instances for ZTE
- **Lesson 008**: Agentic layer context management

## Notes

- Output styles from elite-context-engineering repo (concise-done.md, etc.) are valuable patterns but may be better suited as examples in memory files rather than separate plugin components
- Context bundle hooks (context_bundle_builder.py) demonstrate advanced patterns but require project-specific hook setup
- TypeScript SDK wrapper patterns are reference material for SDK-based orchestration

---

**Plan Created:** 2025-12-04
**Status:** Ready for Implementation
