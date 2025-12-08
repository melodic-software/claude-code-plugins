---
description: Generate a new agentic prompt at specified level (1-7) using meta-prompting
argument-hint: [level] [purpose-description]
---

# Create Prompt

Generate a new prompt at specified level.

## Arguments

- `$1`: Level (1-7)
- `$ARGUMENTS`: High-level description of prompt purpose (after level)

## Instructions

You are creating a new agentic prompt at the specified level.

### Step 1: Parse Arguments

Extract:

- Level from `$1` (1-7, default to 2 if not specified)
- Description from remaining arguments

If no description provided, STOP and ask user for prompt purpose.

### Step 2: Determine Level Requirements

Based on level, identify required sections:

| Level | Required Sections |
| ------- | ------------------- |
| 1 | Title, High-Level Prompt |
| 2 | Title, Variables, Workflow, Report |
| 3 | Title, Variables, Workflow (with control flow) |
| 4 | Title, Variables, Workflow (with delegation) |
| 5 | Title, Variables, Workflow (accepts prompt input) |
| 6 | Title, Variables, Workflow, Specified Format |
| 7 | Title, Variables, Workflow, Expertise |

### Step 3: Design Variables

Determine:

- Dynamic variables (what user provides)
- Static variables (fixed values)
- Default values where appropriate

### Step 4: Design Workflow

Create numbered steps appropriate for the level:

- Level 1: Simple sequential instructions
- Level 2: Input -> Process -> Output pattern
- Level 3: Add conditionals, loops, STOP conditions
- Level 4: Add Task tool delegation
- Level 5: Accept prompt file as input
- Level 6: Include template generation
- Level 7: Include expertise accumulation

### Step 5: Generate Prompt

Create the prompt following the level structure.

### Step 6: Save and Report

## Output

Generate the prompt and provide summary:

```markdown
## Prompt Created

**Name:** [kebab-case-name]
**Level:** [level]
**Location:** .claude/commands/[name].md

### Structure
- Sections: [list]
- Variables: [count] dynamic, [count] static
- Workflow: [count] steps

### Usage
```bash
/[name] [arguments]
```

### Next Steps

- Test the prompt
- Refine based on results
- Consider upgrading if needed

```text

## Notes

- See @seven-levels.md for level definitions
- See @prompt-sections-reference.md for section guidelines
- See @variable-patterns.md for variable conventions
- Use @prompt-level-selection skill if unsure about level
