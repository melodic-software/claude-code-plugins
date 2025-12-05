# Generate Feature Documentation

Generate concise markdown documentation from implemented changes.

## Variables

- `adw_id`: $1 - Workflow identifier (optional)
- `spec_path`: $2 - Path to original specification (optional)

## Purpose

Documentation answers: **"How does it work?"**

Generate reference documentation for implemented features that future agents and developers can use.

## Instructions

### 1. Analyze Changes

Understand what was implemented:

```bash
# See summary of changes
git diff origin/main --stat

# List changed files
git diff origin/main --name-only

# See detailed changes for significant files
git diff origin/main -- path/to/file
```

### 2. Read Specification (if provided)

If spec_path is provided:

- Understand original requirements
- Frame documentation around "what was requested vs what was built"
- Note any deviations or enhancements

### 3. Generate Documentation

Create documentation file: `docs/feature-{descriptive-name}.md`

## Documentation Format

```markdown
# [Feature Title]

**Date**: [Current date]
**Specification**: [spec_path or N/A]

## Overview

[2-3 sentence summary of what was built]

## What Was Built

- [Component/feature 1]
- [Component/feature 2]
- [Component/feature 3]

## Technical Implementation

### Files Modified

- `path/to/file.ts`: [Brief description of changes]
- `path/to/other.ts`: [Brief description of changes]

### Key Changes

- [Important implementation detail 1]
- [Important implementation detail 2]

## How to Use

1. [Step 1 for using the feature]
2. [Step 2 for using the feature]

## Configuration

[Environment variables, settings, or options if applicable]

## Testing

[How to test this feature]

## Notes

[Any additional context, known limitations, or future considerations]
```

### 4. Update Conditional Docs (if applicable)

If conditional documentation exists, add entry for new documentation:

```markdown
- docs/feature-{name}.md
  - Conditions:
    - When working with [feature area]
    - When implementing [related functionality]
```

## Output

Return ONLY the path to the documentation file created:

```text
docs/feature-export-to-csv.md
```

## Best Practices

1. **Concise**: Documentation should be scannable
2. **Accurate**: Reflect what was actually built
3. **Actionable**: Include how to use the feature
4. **Current**: Keep it updated as features change
5. **Linked**: Reference related documentation

## Documentation as Feedback Loop

> "Documentation provides feedback on work done for future agents to reference in their work."

Good documentation enables:

- Future agents to understand the codebase
- Developers to onboard faster
- Consistent patterns to be followed
- Knowledge to persist across sessions

## Integration with Workflow

Documentation typically follows review:

```text
/plan → /implement → /test → /review → /document (THIS COMMAND)
```

Documentation is the final step that captures what was built.
