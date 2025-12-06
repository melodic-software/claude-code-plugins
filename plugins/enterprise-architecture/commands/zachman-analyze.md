---
description: Analyze from Zachman perspective (row: planner/owner/designer/builder/subcontractor/user, column: what/how/where/who/when/why)
argument-hint: [row] [column]
allowed-tools: Read, Glob, Grep, Skill
---

# Zachman Framework Analysis

Analyze architecture from a specific Zachman Framework perspective.

## Arguments

`$ARGUMENTS` - Row and column specification:

**Rows (Perspectives):**

- `planner` or `1` - Executive/Planner (Scope/Context)
- `owner` or `2` - Business Owner (Business Model)
- `designer` or `3` - Architect/Designer (Logical Design)
- `builder` or `4` - Developer/Builder (Physical Design)
- `subcontractor` or `5` - Implementer/Subcontractor (Detailed Specs)
- `user` or `6` - Operations/User (Running System)

**Columns (Interrogatives):**

- `what` or `1` - Data (things of interest)
- `how` or `2` - Function (processes)
- `where` or `3` - Network (locations)
- `who` or `4` - People (roles)
- `when` or `5` - Time (events)
- `why` or `6` - Motivation (goals)

## Workflow

1. **Invoke the zachman-analysis skill** with row/column arguments
2. **If no arguments provided**, enter wizard mode:
   - Ask about the target audience (determines row)
   - Ask about the question being answered (determines column)
3. **Analyze from the specified perspective**:
   - For rows 4-6: Extract information from codebase
   - For rows 1-3: Guide user to provide necessary input
4. **Report findings** with clear limitation notices

## Example Usage

```bash
/ea:zachman-analyze builder what
/ea:zachman-analyze 4 1
/ea:zachman-analyze designer how
/ea:zachman-analyze           # Wizard mode
```

## Output

Analysis from the specified Zachman perspective with clear indication of what was extracted from code vs what requires human input.
