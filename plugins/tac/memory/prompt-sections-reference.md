# Prompt Sections Reference

Composable sections that work like LEGO blocks. Swap them in and out to build prompts at any level.

## Section Tier List

### S-Tier Usefulness

| Section | Purpose | Critical For |
| --------- | --------- | -------------- |
| **Workflow** | Sequential numbered task list | Levels 2-7 |

The Workflow section is the most important section. It's the step-by-step play for your agent to execute.

### A-Tier Usefulness

| Section | Purpose | Critical For |
| --------- | --------- | -------------- |
| **Variables** | Dynamic ($1, $ARGUMENTS) and static inputs | Levels 2+ |
| **Examples** | Concrete usage scenarios | Complex prompts |
| **Control Flow** | Conditionals, loops, early exits | Level 3+ |
| **Delegation** | Task tool patterns, parallel agents | Level 4+ |
| **Template** | Specified format for meta-prompts | Level 6 |

### B-Tier Usefulness

| Section | Purpose | Critical For |
| --------- | --------- | -------------- |
| **Purpose** | What the prompt accomplishes | All levels |
| **High-Level Prompt** | Simple description (Level 1) | Level 1 |
| **Higher Order** | Processing other prompts | Level 5 |
| **Instructions** | Rules, constraints, edge cases | Complex prompts |

### C-Tier Usefulness

| Section | Purpose | Critical For |
| --------- | --------- | -------------- |
| **Metadata** | YAML frontmatter configuration | When needed |
| **Codebase Structure** | Expected directory layout | Project-specific |
| **Relevant Files** | Files the prompt needs | Project-specific |
| **Report** | Output format specification | When structured output needed |

## Section Definitions

### Metadata (Frontmatter)

YAML configuration at the top of the prompt.

```yaml
---
description: Brief description for discovery
argument-hint: [arg1] [arg2]
allowed-tools: Read, Write, Edit, Bash
model: sonnet
---
```markdown

**Fields:**

- `description`: Used for auto-delegation and team discovery
- `argument-hint`: Guide users on expected parameters
- `allowed-tools`: Restrict available tools
- `model`: sonnet, opus, haiku, or full model ID

### Title

H1 heading naming the prompt.

```markdown
# Quick Plan
```markdown

Every prompt starts with a clear, action-oriented title.

### Purpose

1-2 sentences describing what the prompt accomplishes.

```markdown
## Purpose
Create a detailed implementation plan based on the user's requirements.
```markdown

Direct language to agent. References key sections.

### Variables

Define input parameters.

```markdown
## Variables

# Dynamic (from user)
USER_PROMPT: $ARGUMENTS
FILE_PATH: $1
COUNT: $2 or 3 if not provided

# Static (fixed)
OUTPUT_DIR: specs/
MODEL: sonnet
```markdown

**Conventions:**

- SCREAMING_SNAKE_CASE for names
- Dynamic variables first
- Static variables second
- Default values with `or X if not provided`

### Instructions

Rules, constraints, and edge cases.

```markdown
## Instructions

- IMPORTANT: Always validate input before processing
- Handle edge cases gracefully
- If no input provided, STOP and ask user
- Never modify files outside the project directory
```markdown

Bullet points with explicit behavior requirements.

### Workflow

The S-tier section. Sequential task execution.

```markdown
## Workflow

1. Validate inputs
   - Check USER_PROMPT is provided
   - If not, STOP and ask user
2. Analyze requirements
3. Design solution
4. Generate output
   <output-loop>
   - Create artifact
   - Validate artifact
   </output-loop>
5. Report results
```markdown

**Best Practices:**

- Numbered steps for sequence
- Sub-bullets for details
- `<tag>` blocks for loops
- STOP conditions for early exit

### Control Flow

Embedded in Workflow section.

```markdown
## Workflow

1. Check preconditions
   - If X is missing, STOP immediately
   - If Y is invalid, ask user to correct
2. Branch on input type
   - If type is A, execute path A
   - If type is B, execute path B
   - Otherwise, default path
3. Iterate over collection
   <item-loop>
   - Process item
   - Validate result
   </item-loop>
```markdown

### Report

Output format specification.

```markdown
## Report

```markdown
## Implementation Complete

**Files Changed:** [count]
**Lines Modified:** [count]

### Changes Made
- [change 1]
- [change 2]

### Validation
- [ ] Tests pass
- [ ] Linting clean
```markdown

Provides template for structured output.

### Template (Level 6)

Specified format for meta-prompt output.

```markdown
## Specified Format

```md
---
allowed-tools: <tools>
description: <description>
---

# <name>

## Variables
<DYNAMIC_VAR>: $1

## Workflow
<numbered steps>
```markdown

The template the meta-prompt fills in.

### Expertise (Level 7)

Accumulated knowledge for self-improving prompts.

```markdown
## Expertise

### Hook Architecture Knowledge
- PreToolUse/PostToolUse for tool interception
- JSONL format enables streaming append
- Session-based directories for organization

### Discovered Patterns
- Multiple hooks can target same event
- Non-blocking exit codes prevent disruption
```yaml

Evolves over time as agent learns.

## Section Combinations by Level

| Level | Required | Common | Optional |
| ------- | ---------- | -------- | ---------- |
| 1 | Title, Prompt | - | - |
| 2 | Title, Workflow | Variables, Report | Instructions |
| 3 | Title, Workflow | Variables, Control Flow | Report |
| 4 | Title, Workflow | Variables, Delegation | Report |
| 5 | Title, Workflow | Variables | Instructions |
| 6 | Title, Workflow, Template | Variables | Instructions |
| 7 | Title, Workflow, Expertise | Variables | Instructions |

## Key Quote

> "Build libraries of reusable battle-tested agentic prompts with composable sections that work like LEGO blocks."

---

**Cross-References:**

- @seven-levels.md - Level-by-level framework
- @variable-patterns.md - Variable handling details
- @stakeholder-trifecta.md - Communication for each audience
