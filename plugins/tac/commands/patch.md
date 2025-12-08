---
description: Create minimal surgical patch plan for targeted fix
argument-hint: [change-request] [spec-path]
---

# Create Focused Patch Plan

Create a minimal, surgical patch plan to address a specific issue.

## Variables

- `review_change_request`: $1 - Description of the issue to fix
- `spec_path`: $2 (optional) - Path to original specification

## Purpose

Create a PATCH - minimal scope, surgical fix, targeted change.

> "This is a PATCH - keep the scope minimal. Only fix what's described in the review_change_request and nothing more."

## Instructions

### 1. Understand the Issue

Parse the review_change_request:

- What exactly is broken?
- What is the expected behavior?
- What evidence exists (screenshots, errors)?

Do NOT expand scope beyond this specific issue.

### 2. Read Original Spec (if provided)

If spec_path is provided, read it for context:

- Original requirements
- How this issue relates to the spec
- What was the intended behavior

### 3. Analyze Current State

```bash
# See current changes
git diff --stat

# Find relevant files
grep -r "related_term" src/
```

### 4. Determine Minimum Fix

Ask: "What is the smallest change that fixes this?"

- Prefer 1-10 line changes
- Avoid refactoring
- Don't fix unrelated issues

### 5. Create Patch Plan

Write to: `specs/patch/patch-{descriptive-name}.md`

## Plan Format

```markdown
# Patch: [Concise patch title]

## Metadata
- Review Change Request: [from input]
- Spec Path: [if provided]

## Issue Summary
**Problem**: [What's broken - specific]
**Solution**: [Minimal fix approach]

## Files to Modify
[Only files that need changes - specific and minimal]

- `path/to/file.ts`: [What change is needed]

## Implementation Steps

IMPORTANT: Execute every step in order, top to bottom.

### Step 1: [Specific action]
[Exact code change needed]

### Step 2: [Specific action]
[Exact code change needed]

## Validation
Execute every command to validate patch is complete:

- [Specific test command]
- [Manual verification step]

## Patch Scope
- **Lines of code to change**: [estimate]
- **Risk level**: [low/medium/high]
- **Testing required**: [minimal/standard/extensive]
```

## Output

Return ONLY the path to the patch plan file created:

```text
specs/patch/patch-fix-button-disabled-state.md
```

## Scope Guidelines

**Keep Minimal:**

- Fix only the reported issue
- Don't refactor surrounding code
- Don't add unrelated improvements
- Don't update documentation

**Risk Assessment:**

| Lines | Risk |
| ------- | ------ |
| 1-10 | Low |
| 10-50 | Medium |
| 50+ | High - reconsider scope |

## Integration with Workflow

Patches typically follow review:

```text
/review → Identifies blocker issue
  ↓
/patch → Creates surgical fix plan (THIS COMMAND)
  ↓
/implement → Executes patch plan
  ↓
/review → Re-verifies fix
```
