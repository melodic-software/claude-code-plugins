---
description: Comprehensive code review using code-reviewer agent with code-quality:code-reviewing skill
argument-hint: [files or 'staged' or 'pr' or '--parallel' or '--sequential']
allowed-tools: Task, Bash, Read, Glob, Grep
---

# Code Review Command

Run comprehensive code review on specified files or staged changes.

## Instructions

**Use the code-reviewer agent to perform systematic code quality analysis.**

The code-reviewer agent provides:

- **Tiered progressive disclosure** for token optimization
- **Security analysis** (OWASP top 10, secrets detection)
- **Performance review** (N+1 queries, resource leaks)
- **Code quality** (SOLID, DRY, clean code principles)
- **CLAUDE.md compliance** for Claude Code ecosystem files
- **Severity levels** (CRITICAL/MAJOR/MINOR)

**Invoke the agent based on the arguments provided:**

```text
$ARGUMENTS

Based on the arguments, determine the review scope:

If 'staged' or no arguments:
  - Review currently staged files (git diff --staged)
  - Good for pre-commit review

If 'pr' or 'pull-request':
  - Review all changes in the current PR/branch vs main
  - Good for PR review

If specific file paths provided:
  - Review those specific files
  - Can be globs like "src/**/*.ts"

If '--parallel':
  - Run multiple code-reviewer agents in parallel (one per file/module)
  - Good for large changesets

If '--sequential':
  - Run single code-reviewer agent reviewing all files
  - Good for smaller changesets or when context between files matters

Default: staged changes, sequential mode
```

## Examples

### Review Staged Changes

```text
/code-quality:review
/code-quality:review staged
```

### Review PR Changes

```text
/code-quality:review pr
```

### Review Specific Files

```text
/code-quality:review src/auth.ts src/config.ts
/code-quality:review "src/**/*.ts"
```

### Parallel Review (Large Changesets)

```text
/code-quality:review --parallel
/code-quality:review pr --parallel
```

## Output Format

The agent returns a structured review report:

```markdown
## Review Summary
**Files Reviewed**: [Count]
**Issues Found**: [CRITICAL: X | MAJOR: Y | MINOR: Z]
**Overall Assessment**: [PASS/CONCERNS/FAIL]

## Critical Issues
[Details with file:line, problem, impact, fix]

## Major Issues
[Details]

## Minor Issues
[Details]

## Positive Observations
[Good patterns noted]
```

## Command Design Notes

This command delegates to the code-reviewer agent, which uses the code-quality:code-reviewing skill as its authoritative source. The skill provides tiered checklists and repository-specific rules. This separation keeps the command simple while leveraging comprehensive review logic.
