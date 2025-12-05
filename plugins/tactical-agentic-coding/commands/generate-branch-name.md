---
description: Generate a semantic Git branch name from issue context for ADW workflows.
---

# Branch Name Generation

Generate a semantic Git branch name following the convention.

## Branch Naming Convention

```text
{type}-{issue_number}-{short_id}-{slug}
```yaml

Components:

- **type**: `feat`, `fix`, `chore` (from issue classification)
- **issue_number**: GitHub issue number
- **short_id**: 8-character identifier (ADW ID if provided)
- **slug**: Kebab-case summary of issue (max 30 chars)

## Examples

```text
feat-123-a1b2c3d4-add-user-auth
fix-456-e5f6g7h8-login-double-submit
chore-789-i9j0k1l2-update-dependencies
```markdown

## Rules

1. Use lowercase letters, numbers, and hyphens only
2. No spaces or special characters in slug
3. Slug should be descriptive but concise (max 30 chars)
4. Response should be ONLY the branch name, nothing else

## Input Variables

- **$1**: Issue type (`feat`, `fix`, `chore`)
- **$2**: Short ID (8 characters, or generate one)
- **$ARGUMENTS**: Issue title or description

## Generation Process

1. Take the issue type from $1
2. Extract issue number if present in arguments
3. Use provided short ID from $2 or generate 8 random hex chars
4. Create slug from issue description:
   - Convert to lowercase
   - Replace spaces with hyphens
   - Remove special characters
   - Truncate to 30 characters
   - Remove trailing hyphens

## Issue Context

Type: $1
ID: $2
Issue: $ARGUMENTS
