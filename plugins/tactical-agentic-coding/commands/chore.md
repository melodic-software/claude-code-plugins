---
description: Generate a comprehensive chore plan from a one-line description using meta-prompt template engineering.
---

# Chore Planning

Create a new plan in `specs/*.md` to resolve the Chore using the exact specified markdown Plan Format. Follow the Instructions to create the plan, use the Relevant Files to focus on the right files.

## Instructions

- You are writing a plan to resolve a chore, NOT implementing it yet
- Use your reasoning model: THINK HARD about the plan and the steps to accomplish the chore
- Read the codebase to understand current patterns and structure
- Focus on the files in the Relevant Files section when identifying what to modify
- Fill in EVERY section of the Plan Format - no empty sections
- Include realistic validation commands that actually verify completion
- Keep the plan focused - don't expand scope beyond the chore description

## Relevant Files

Focus on the following files to understand the codebase:

- README.md (project structure and conventions)
- CLAUDE.md (agent instructions if present)
- src/**or app/** (source code patterns)
- scripts/** (existing automation)
- tests/** (test patterns to follow)

## Plan Format

Write the plan to `specs/chore-<descriptive-name>.md` using this exact format:

```markdown
# Chore: <descriptive-name>

## Chore Description
<Clear explanation of what needs to be done and why this is valuable>

## Relevant Files
<List all files that will be created, modified, or deleted>

## Step by Step Tasks
1. <First specific, actionable task>
2. <Second specific task with file references>
3. <Continue with numbered tasks>

## Validation Commands
<Commands that prove the work is complete>
- Run `<command>` to verify <what>
- Run `<command>` to verify <what>

## Notes
<Edge cases, dependencies, gotchas, or related work to consider>
```markdown

## Chore

$ARGUMENTS
