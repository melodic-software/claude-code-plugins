---
description: Review architecture of current codebase or staged changes
argument-hint: [files or 'staged']
allowed-tools: Task, Read, Glob, Grep, Skill
---

# Architecture Review

Perform comprehensive architecture review including viewpoint analysis and principles validation.

## Arguments

`$ARGUMENTS` - Scope of review:

- Specific file paths or patterns
- `staged` - Review staged git changes
- (empty) - Review entire codebase

## Workflow

1. **Spawn parallel analysis agents**:
   - **viewpoint-analyzer** - Analyze from multiple stakeholder perspectives
   - **principles-validator** - Check alignment with architecture principles

2. **viewpoint-analyzer will**:
   - Identify relevant Zachman perspectives
   - Analyze from each applicable viewpoint
   - Note limitations for rows 1-3 (require human input)

3. **principles-validator will**:
   - Load architecture principles (from `/architecture/principles.md` or memory)
   - Check specified files/changes against each principle
   - Report violations with severity (critical, warning, info)
   - Link violations to relevant ADRs

4. **Aggregate results** into comprehensive review report

## Example Usage

```bash
/ea:architecture-review
/ea:architecture-review staged
/ea:architecture-review src/api/
/ea:architecture-review src/auth/*.ts
```

## Output

Comprehensive architecture review report including:

- Viewpoint analysis results
- Principles compliance status
- Violations with severity and remediation suggestions
- Links to relevant ADRs
