---
description: Compare implementation against specification to verify alignment
argument-hint: [spec-file-path]
---

# Review Implementation Against Spec

Compare the implementation against the specification to verify alignment.

## Variables

- `spec_file`: $1 - Path to the specification file

## Purpose

Review answers: **"Is what we built what we asked for?"**

This is different from testing. We know functionality works. We're validating alignment with the original specification.

## Instructions

### 1. Read the Specification

Read the spec file to understand:

- Original requirements
- Success criteria
- Expected behavior
- Acceptance criteria

### 2. Analyze Changes

Compare implementation against spec:

```bash
# See all changes
git diff origin/main

# See changed files
git diff origin/main --stat

# See specific file changes
git diff origin/main -- path/to/file
```

### 3. Capture Screenshots (1-5)

Take screenshots of critical functionality paths:

1. **Initial State**: Before interaction
2. **Key Actions**: After significant user actions
3. **Final State**: End result

Name format: `01_descriptive_name.png`, `02_descriptive_name.png`

### 4. Compare Against Spec

For each requirement in the spec:

- Is it implemented?
- Does it match the specification?
- Are there any deviations?

### 5. Classify Issues

For each issue found, classify by severity:

| Severity | Description | Action |
| ---------- | ------------- | -------- |
| **blocker** | Prevents release, harms UX | Must fix |
| **tech_debt** | Quality issue, feature works | Document |
| **skippable** | Polish, preference | Note only |

## Output Format

Return ONLY JSON:

```json
{
  "success": true,
  "review_summary": "2-4 sentence summary of review findings",
  "review_issues": [
    {
      "issue_description": "Clear description of the issue",
      "issue_resolution": "How to fix it",
      "issue_severity": "blocker"
    },
    {
      "issue_description": "Another issue",
      "issue_resolution": "Resolution approach",
      "issue_severity": "tech_debt"
    }
  ],
  "screenshots": [
    "path/to/01_initial_state.png",
    "path/to/02_after_action.png"
  ]
}
```

## Success Criteria

- `success: true` when NO blocker issues exist
- `success: false` when ANY blocker issues exist

Review can succeed with tech_debt and skippable issues.

## Classification Guidelines

**Blocker if:**

- Feature doesn't work as specified
- UI doesn't match requirements
- Critical functionality missing
- User experience is harmed

**Tech Debt if:**

- Feature works but implementation is suboptimal
- Code quality issues
- Missing optimization
- Console warnings

**Skippable if:**

- Minor visual differences
- Polish improvements
- Subjective preferences
- Nice-to-have enhancements

## Integration with Workflow

This command is part of the SDLC:

```text
/plan → /implement → /test → /review → /patch (if needed) → /document
```

If blockers are found, use `/patch` to create targeted fixes.
