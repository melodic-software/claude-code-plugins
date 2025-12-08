# Template Engineering

Encode your engineering workflows and best practices into reusable, scalable units of agentic success.

## What is a Meta-Prompt?

A **meta-prompt** is a prompt that builds a prompt. Instead of writing a plan from scratch every time, you create a template that generates plans based on high-level input.

```text
High-Level Input --> Meta-Prompt Template --> Detailed Plan
```markdown

This is one of the most powerful leverage points in agentic coding - you stop writing plans manually and let agents generate them using your encoded best practices.

## Template Anatomy

Every great template contains five sections:

### 1. Purpose

Clear description at the top explaining what this template does:

```markdown
# Chore Planning

Create a new plan in specs/*.md to resolve the Chore using the
exact specified markdown Plan Format.
```markdown

### 2. Instructions

Detailed guidance for the agent on how to approach the task:

```markdown
## Instructions

- You are writing a plan to resolve a chore, not implementing it
- Use your reasoning model: THINK HARD about the plan
- Focus on the files in Relevant Files section
- Include validation commands that verify completion
```markdown

### 3. Relevant Files

File paths the agent should focus on - guides context loading:

```markdown
## Relevant Files

Focus on the following files:
- README.md
- app/**
- scripts/**
- tests/**
```markdown

### 4. Plan Format

Markdown template with placeholders the agent fills in:

```markdown
## Plan Format

# Chore: <name>

## Chore Description
<description of what needs to be done>

## Relevant Files
<list files that will be modified>

## Step by Step Tasks
<numbered list of specific tasks>

## Validation Commands
<commands to verify work is complete>

## Notes
<edge cases, considerations, dependencies>
```markdown

### 5. Parameter

The `$ARGUMENTS` variable that accepts user input:

```markdown
## Chore
$ARGUMENTS
```markdown

## Design Principles

### Solve Problem Classes, Not Problems

Templates let you solve entire classes of problems:

| Template | Solves |
| ---------- | -------- |
| `/chore` | All maintenance tasks |
| `/bug` | All bug investigations and fixes |
| `/feature` | All new feature implementations |

One template, infinite uses.

### Encode Team Best Practices

Your templates become a living library of engineering expertise:

- **Your** bug investigation process
- **Your** testing requirements
- **Your** code review standards
- **Your** documentation format

Anyone on your team can execute with your quality standards.

### Always Include Validation Commands

Every plan should include commands that verify completion:

```markdown
## Validation Commands

- Run `pytest tests/` to verify all tests pass
- Run `ruff check .` to verify no linting errors
- Run `npm run build` to verify build succeeds
```markdown

This creates closed-loop systems where agents can self-validate.

## Example: Chore Template

```markdown
# Chore Planning

Create a new plan in specs/*.md to resolve the Chore using the
exact specified markdown Plan Format. Follow the Instructions
to create the plan, use the Relevant Files to focus.

## Instructions

- You're writing a plan to resolve a chore, not implementing
- Use your reasoning model: THINK HARD about the plan
- Fill in every section of the Plan Format
- Include realistic validation commands

## Relevant Files

Focus on: README.md, app/**, scripts/**, tests/**

## Plan Format

# Chore: <name>

## Chore Description
<what needs to be done and why>

## Relevant Files
<files to create/modify/delete>

## Step by Step Tasks
<specific actionable steps>

## Validation Commands
<commands that prove completion>

## Notes
<edge cases, gotchas, related work>

## Chore
$ARGUMENTS
```markdown

## Anti-Patterns

### Agents Without Structure

Having agents run loose on your codebase without templates is a plan for failure. Structure ensures:

- Consistent quality
- Reproducible results
- Team-wide standards

### Manual Planning

Writing every plan from scratch wastes your most valuable resource: time. Templates turn one-line descriptions into comprehensive plans.

### Missing Validation

Plans without validation commands cannot be verified. Always include:

- Test commands
- Lint commands
- Build commands
- Custom verification scripts

## Related Memory Files

- @meta-prompt-patterns.md - Prompt hierarchy and composition
- @plan-format-guide.md - Standard plan structures
- @fresh-agent-rationale.md - Why use fresh agent instances
