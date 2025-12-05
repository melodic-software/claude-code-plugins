---
description: Generate a comprehensive bug fix plan with root cause analysis from a bug description using meta-prompt template engineering.
---

# Bug Fix Planning

Create a new plan in `specs/*.md` to investigate and fix the Bug using the exact specified markdown Plan Format. Follow the Instructions to create the plan, use the Relevant Files to focus on the right files.

## Instructions

- You are writing a plan to fix a bug, NOT implementing the fix yet
- Use your reasoning model: THINK HARD about the root cause and solution
- Investigate the codebase to understand how the bug could occur
- Focus on the files in the Relevant Files section when identifying what to modify
- Fill in EVERY section of the Plan Format - the Root Cause Analysis is critical
- Include validation commands that prove the bug is fixed AND doesn't regress
- Consider related code that might have similar issues

## Relevant Files

Focus on the following files to understand the codebase:

- README.md (project structure)
- CLAUDE.md (agent instructions if present)
- src/**or app/** (source code to investigate)
- tests/** (existing tests and test patterns)
- Error logs or stack traces if provided

## Plan Format

Write the plan to `specs/bug-<descriptive-name>.md` using this exact format:

```markdown
# Bug: <descriptive-name>

## Bug Description
<Clear explanation of the bug and its user impact>

## Problem Statement
<What is happening that should not be happening>

## Solution Statement
<What should happen instead - the expected behavior>

## Steps to Reproduce
1. <Step to reproduce the bug>
2. <Continue steps>
3. <Final step showing the bug>
   - Expected: <what should happen>
   - Actual: <what actually happens>

## Root Cause Analysis
<Investigation findings explaining WHY this bug occurs>

## Relevant Files
<Files involved in the bug and the fix>

## Step by Step Tasks
1. <First fix task with specific file and line references>
2. <Continue with numbered tasks>

## Validation Commands
<Commands that verify the bug is fixed>
- Run `<test command>` to verify the fix
- Reproduce steps above to confirm resolution
- Run `<test suite>` to check for regressions

## Notes
<Related bugs, regression risks, areas to monitor>
```

## Bug

$ARGUMENTS
