# Lesson 3 Analysis: Success is Planned - The 80-20 of Agentic Coding

## Content Summary

### Core Tactic

**Template Your Engineering** - Encode your engineering workflows and best practices into reusable, scalable units of agentic success. By encoding problem-solving patterns into templates, you create a living library of engineering expertise that your agents can consistently execute with high precision across sets of problems.

### Key Frameworks

#### The 80-20 of Agentic Coding (First Three Tactics)

| # | Tactic | Description |
| - | ------ | ----------- |
| 1 | **Stop Coding** | Your hands and mind are no longer the best tools for writing code |
| 2 | **Adopt Agent's Perspective** | Understand what your agent can see and do |
| 3 | **Template Your Engineering** | Encode problem-solving into reusable units |

#### Prompt Hierarchy

| Level | Type | Description |
| ----- | ---- | ----------- |
| 1 | **High-Level Prompt** | Simple description void of detail (input) |
| 2 | **Meta-Prompt** | Prompt that builds a prompt (template) |
| 3 | **Plan** | Generated detailed specification (output) |
| 4 | **Higher-Order Prompt (HOP)** | Prompt that accepts another prompt as input |

#### Phase 2 SDLC (Agentic)

```bash
Plan -> Code -> Test -> Review -> Document
```

### Implementation Patterns from Repo (tac-3)

1. **Chore Template** (`/chore`) - Meta-prompt for chore-type work:

   ```markdown
   # Chore Planning

   Create a new plan in specs/*.md to resolve the `Chore` using the exact
   specified markdown `Plan Format`. Follow the `Instructions` to create
   the plan use the `Relevant Files` to focus on the right files.

   ## Instructions
   - You're writing a plan to resolve a chore...
   - Use your reasoning model: THINK HARD about the plan...

   ## Relevant Files
   Focus on the following files: README.md, app/**, scripts/**

   ## Plan Format
   [Template with placeholders]

   ## Chore
   $ARGUMENTS
   ```

2. **Bug Template** (`/bug`) - Meta-prompt for bug fixes:
   - Includes: Problem Statement, Solution Statement, Steps to Reproduce
   - Root Cause Analysis section
   - More detailed validation than chores

3. **Feature Template** (`/feature`) - Meta-prompt for new features:
   - User Story section
   - Implementation Plan (Foundation, Core, Integration phases)
   - Testing Strategy (Unit, Integration, Edge Cases)
   - Acceptance Criteria

4. **Implement Command** (`/implement`) - Higher-Order Prompt:

   ```markdown
   # Implement the following plan
   Follow the `Instructions` to implement the `Plan` then `Report`.

   ## Instructions
   - Read the plan, think hard about the plan and implement the plan.

   ## Plan
   $ARGUMENTS

   ## Report
   - Summarize the work you've just done in a concise bullet point list.
   - Report the files and total lines changed with `git diff --stat`
   ```

5. **Prime Command** (`/prime`) - Context priming:

   ```markdown
   # Prime
   > Execute the following sections to understand the codebase then summarize.

   ## Run
   git ls-files

   ## Read
   README.md
   ```

6. **Install Command** (`/install`) - Composable setup:

   ```markdown
   # Install & Prime
   ## Read and Execute
   .claude/commands/prime.md
   ## Run
   Install FE and BE dependencies
   Run `./scripts/copy_dot_env.sh` to copy the .env file.
   ## Report
   Output the work you've just done in a concise bullet point list.
   ```

### Template Anatomy

Every great template contains:

1. **Purpose** - Clear description at the top
2. **Instructions** - Detailed guidance for the agent
3. **Relevant Files** - File paths to focus on
4. **Plan Format** - Markdown template with `<placeholders>`
5. **Parameter** - `$ARGUMENTS` for user input

### Why Fresh Agent Instances

Three critical reasons for running new agent instances:

| # | Reason | Description |
| - | ------ | ----------- |
| 1 | **Free Context** | Focus every available token on the task at hand |
| 2 | **Force Isolation** | Make prompts, plans, templates isolated, reusable, improvable assets with zero dependencies |
| 3 | **Prepare for Off-Device** | Prepare for true off-device agentic coding where agents run without your presence |

### Anti-Patterns Identified

- **Agents without structure**: Having agents run loose without templates is a plan for failure
- **Stretched agent context**: Using one agent across entire SDLC depletes context window
- **Conversational dependence**: Relying on multi-turn conversation instead of one-shot plans
- **Manual planning**: Writing all plans yourself instead of using meta-prompts

### Metrics/KPIs

- **Template reuse rate**: How often templates are used across the team
- **Plan generation time**: Time from high-level prompt to comprehensive plan
- **One-shot success rate**: Plans that work on first execution

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `template-engineering` | Guide creation of meta-prompt templates | template, meta-prompt, plan, encode |
| `plan-generation` | Assist in generating plans from templates | plan, spec, generate, specification |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `plan-generator` | Generate plans from templates using reasoning mode | Read, Write, Glob, Grep |
| `plan-implementer` | Execute generated plans with validation | Read, Write, Edit, Bash |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/chore` | Generate chore plan from template | `$ARGUMENTS` - chore description |
| `/bug` | Generate bug fix plan from template | `$ARGUMENTS` - bug description |
| `/feature` | Generate feature plan from template | `$ARGUMENTS` - feature description |
| `/implement` | Execute a generated plan | `$ARGUMENTS` - path to plan file |
| `/prime` | Prime agent with codebase context | None |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `template-engineering.md` | Template creation best practices and anatomy | When creating templates |
| `meta-prompt-patterns.md` | Meta-prompt and HOP patterns | When building prompt hierarchies |
| `plan-format-guide.md` | Standard plan format sections | When generating/reviewing plans |
| `fresh-agent-rationale.md` | Why and when to use fresh instances | When deciding agent lifecycle |

## Key Insights for Plugin Development

### High-Value Components from Lesson 3

1. **Template Command System**
   - `/chore`, `/bug`, `/feature` as meta-prompts
   - `/implement` as higher-order prompt
   - Each generates plans in `specs/` directory

2. **Memory File: `template-engineering.md`**
   - Template anatomy (Purpose, Instructions, Relevant Files, Format, Parameter)
   - Meta-prompt design patterns
   - Higher-Order Prompt composition

3. **Memory File: `plan-format-guide.md`**
   - Standard sections for each plan type
   - Validation commands section critical
   - Notes section for edge cases

4. **Skill: `template-engineering`**
   - Analyze codebase for template opportunities
   - Generate template scaffolds
   - Validate template structure

### Plan Structure Standards

**Chore Plans:**

```markdown
# Chore: <name>
## Chore Description
## Relevant Files
## Step by Step Tasks
## Validation Commands
## Notes
```

**Bug Plans:**

```markdown
# Bug: <name>
## Bug Description
## Problem Statement
## Solution Statement
## Steps to Reproduce
## Root Cause Analysis
## Relevant Files
## Step by Step Tasks
## Validation Commands
## Notes
```

**Feature Plans:**

```markdown
# Feature: <name>
## Feature Description
## User Story
## Problem Statement
## Solution Statement
## Relevant Files
## Implementation Plan (Foundation, Core, Integration)
## Step by Step Tasks
## Testing Strategy (Unit, Integration, Edge Cases)
## Acceptance Criteria
## Validation Commands
## Notes
```

### Key Quotes

> "Plans are prompts scaled up for high impact. Great planning is great prompting."
> "A meta-prompt is a prompt that builds a prompt."
> "By having this expectation that we're going to run fresh instances, we now have a pattern where we encode templates to solve problems repeatedly."
> "Having agents run loose on your codebase without structure, without knowing how you do things is a plan for failure."
> "We want to decouple our performance from the conversational context window."

### "Think Hard" Activation

The lesson emphasizes using "think hard" to activate Claude Code's reasoning model:

```markdown
## Instructions
- Use your reasoning model: THINK HARD about the plan and the steps to accomplish the chore.
```

This is one of the 12 leverage points - turning on the reasoning model for complex problem solving.

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 46:32 of content!)
- [x] Explored tac-3 repository
- [x] Read .claude/commands/chore.md (chore template)
- [x] Read .claude/commands/bug.md (bug template)
- [x] Read .claude/commands/feature.md (feature template)
- [x] Read .claude/commands/implement.md (HOP)
- [x] Read .claude/commands/prime.md (context priming)
- [x] Read .claude/commands/install.md (composable setup)
- [x] Read .claude/settings.json (permissions)
- [x] Read README.md (project overview)
- [x] Read specs/init_nlq_to_sql_to_table.md (comprehensive spec example - 750 lines!)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 1**: Stop coding - now use templates to automate planning too
- **Builds on Lesson 2**: 12 leverage points - templates are one of them
- **Sets up Lesson 4**: Off-device agentic coding with PITER framework
- **Sets up Lesson 5**: Validation commands create closed loops
- **Sets up Lesson 7**: Fresh agent instances → ZTE (Zero Touch Engineering)

## Notable Implementation Details

### Programmatic Execution

The lesson demonstrates running templates programmatically:

```bash
claude -p "/feature \"create a new query history side panel...\"" \
  --output-format stream \
  --dangerously-skip-permissions \
  --model claude-sonnet-4-20250514 \
  --verbose \
  >> adws/programmatic_claude_feature.jsonl
```

This streams output to a JSONL file for later analysis - key pattern for off-device execution.

### Permission Configuration

```json
{
  "permissions": {
    "allow": [
      "Bash(mkdir:*)", "Bash(uv:*)", "Bash(find:*)", "Bash(mv:*)",
      "Bash(grep:*)", "Bash(npm:*)", "Bash(ls:*)", "Bash(cp:*)",
      "Write", "Bash(./scripts/copy_dot_env.sh:*)",
      "Bash(chmod:*)", "Bash(touch:*)"
    ],
    "deny": [
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Bash(rm -rf:*)"
    ]
  }
}
```

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
