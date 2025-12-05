# The Seven Levels of Agentic Prompts

The prompt is now the fundamental unit of engineering. Every prompt you create becomes a force multiplier. This framework organizes prompts by complexity and capability.

## The Levels

| Level | Name | Key Capability | Complexity |
| ------- | ------ | ---------------- | ------------ |
| 1 | High-Level Prompt | One-off repeatable tasks | Low |
| 2 | Workflow Prompt | Sequential task execution | Low-Medium |
| 3 | Control Flow | Conditionals and loops | Medium |
| 4 | Delegation Prompt | Multi-agent orchestration | Medium-High |
| 5 | Higher-Order Prompts | Prompts processing prompts | High |
| 6 | Template Meta Prompt | Prompts generating prompts | High |
| 7 | Self-Improving Prompt | Self-modifying systems | Very High |

## Level 1: High-Level Prompt

**Definition:** Simple, reusable, static prompt for one-off repeatable tasks.

**Sections:** Title, High-level prompt (1-3 sentences)

**Example:**

```markdown
# Start Development Server

Start the development server for this project.

1. Navigate to project directory
2. Install dependencies: `bun install`
3. Start server: `bun run dev`
```markdown

**Use When:**

- Task is simple and repeatable
- No variables needed
- Sequential instructions suffice
- Three times marks a pattern - write it down

## Level 2: Workflow Prompt (Game Changer)

**Definition:** Sequential workflow with input -> work -> output pattern.

**Sections:** Metadata, Variables, Workflow (S-tier), Instructions, Report

**Example:**

```markdown
---
description: Create implementation plan
model: sonnet
---

# Quick Plan

## Variables
USER_PROMPT: $ARGUMENTS
OUTPUT_DIR: specs/

## Workflow
1. Analyze requirements from USER_PROMPT
2. Design technical approach
3. Document step-by-step plan
4. Save to OUTPUT_DIR/<filename>.md

## Report
File: OUTPUT_DIR/<filename>.md
Topic: <brief description>
```markdown

**Use When:**

- Task has clear sequential steps
- Need input variables
- Want structured output
- The Workflow section is S-tier usefulness

## Level 3: Control Flow

**Definition:** Workflow with conditional logic, branching, and loops.

**Key Patterns:**

- `<loop-tag>` for iteration
- `STOP immediately and ask user` for early exit
- `If X, do Y, otherwise Z` for branching

**Example:**

```markdown
## Workflow
1. Check if `$1` is provided
   - If not provided, STOP immediately and ask user
2. Create output directory
3. Generate NUMBER_OF_IMAGES images:
   <image-loop>
   - Call generation API
   - Wait for completion
   - Save to output directory
   </image-loop>
4. Open output directory
```markdown

**Use When:**

- Need conditional execution
- Iterating over collections
- Early exit conditions exist
- Branching based on input

## Level 4: Delegation Prompt

**Definition:** Prompt that kicks off other workflows and orchestrates agents.

**Key Patterns:**

- Task tool for sub-agents
- Parallel batch launching
- Background process management
- Stateless context transfer

**Example:**

```markdown
## Workflow
1. Parse input parameters
2. Design agent prompts (complete, self-contained)
3. Launch parallel agents:
   - Use Task tool to spawn N agents simultaneously
   - Ensure all agents launch in single parallel batch
4. Collect and summarize results
```markdown

**Use When:**

- Work can be parallelized
- Need specialized sub-agents
- Long-running background tasks
- Complex multi-step orchestration

## Level 5: Higher-Order Prompts

**Definition:** Prompts that accept other prompts as input.

**Key Pattern:** Accept prompt file path, process its contents, execute based on it.

**Example:**

```markdown
## Variables
PATH_TO_PLAN: $ARGUMENTS

## Workflow
- If no PATH_TO_PLAN provided, STOP and ask user
- Read the plan at PATH_TO_PLAN
- Think hard about the plan
- Implement it into the codebase
```markdown

**Use When:**

- Building on generated specifications
- Plan-then-execute patterns
- Context bundle loading
- Template composition

## Level 6: Template Meta Prompt

**Definition:** Prompts that generate other prompts in a specific format.

**Key Pattern:** Include Specified Format template, output new prompts.

**Example:**

```markdown
## Workflow
- Fetch documentation for context
- Design prompt structure
- Output in Specified Format

## Specified Format
```md
---
allowed-tools: <tools>
description: <description>
model: sonnet
---

# <name>

## Variables
<dynamic>: $1
<static>: <value>

## Workflow
<numbered steps>

## Report
<output format>
```markdown

**Use When:**

- Building prompt libraries
- Standardizing team prompts
- Scaffolding new workflows
- Highest leverage - prompts creating prompts

## Level 7: Self-Improving Prompt

**Definition:** Prompts with evolving Expertise sections that improve over time.

**Key Pattern:** Plan-Build-Improve triplet with accumulated knowledge.

**Example:**

```markdown
# Expert Plan

## Expertise
### Discovered Patterns
- Pattern 1 learned from experience
- Pattern 2 discovered during work

## Workflow
1. Read documentation
2. Apply expertise patterns
3. Create specification

---

# Expert Improve

## Workflow
1. Analyze recent changes
2. Extract new learnings
3. Update ## Expertise section in Plan
   - DO NOT modify Workflow sections
```yaml

**Use When:**

- Building domain experts
- Knowledge accumulation needed
- Long-term agent improvement
- Self-modifying systems

## The 80/20 Rule

> "For most practical applications, Levels 3-4 are all you need."

| Level Range | Coverage | Use Case |
| ------------- | ---------- | ---------- |
| 1-2 | 40% | Simple automation |
| 3-4 | 80% | Most practical work |
| 5-7 | 20% | Advanced meta-engineering |

Don't over-engineer. Start simple, add complexity only when needed.

## Level Selection Quick Reference

| Need | Level |
| ------ | ------- |
| Repeat simple task | 1 |
| Sequential workflow | 2 |
| Conditional/loops | 3 |
| Multi-agent work | 4 |
| Process other prompts | 5 |
| Generate prompts | 6 |
| Self-evolving system | 7 |

## Key Quote

> "Three times marks a pattern. Copy whatever you're doing and write it as a high level prompt, then move up the levels from there."

---

**Cross-References:**

- @prompt-sections-reference.md - Composable sections for each level
- @stakeholder-trifecta.md - Engineering for you, team, and agents
- @variable-patterns.md - Dynamic vs static variable handling
