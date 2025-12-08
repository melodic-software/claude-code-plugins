---
description: Classify a GitHub issue into a problem class (chore, bug, or feature) for ADW routing.
---

# Issue Classification

Analyze the issue and respond with exactly one classification.

## Categories

### /chore

Maintenance tasks, updates, cleanup, refactoring:

- Dependency updates
- Code cleanup and formatting
- Documentation improvements
- Refactoring without behavior change

### /bug

Defects, errors, unexpected behavior:

- Something broken that should work
- Crashes, errors, incorrect output
- Regressions from previous functionality
- Performance issues causing failures

### /feature

New functionality, enhancements:

- New user-facing capabilities
- Enhancements to existing features
- New API endpoints or integrations
- UI/UX improvements

## Rules

1. Respond with exactly one: `/chore`, `/bug`, `/feature`, or `0`
2. If the issue fits multiple categories, choose the primary purpose
3. If unclear between chore and feature, prefer `/chore` (safer)
4. If the issue is a question or discussion, respond with `0`
5. Your response should be ONLY the classification, nothing else

## Examples

- "Update dependencies to latest" → `/chore`
- "Login form submits twice" → `/bug`
- "Add dark mode toggle" → `/feature`
- "Question about the API" → `0`

## Issue

$ARGUMENTS
