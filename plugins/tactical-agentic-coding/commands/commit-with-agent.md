---
description: Create a Git commit with agent attribution for ADW workflows.
---

# Commit with Agent Attribution

Create a semantic commit message that attributes the work to the agent.

## Commit Message Format

```text
{agent}: {type}: {description}
```yaml

Components:

- **agent**: Name of the agent that did the work
- **type**: Type of change (feat, fix, chore, docs, refactor, test)
- **description**: Concise description of the change

## Examples

```text
planner: feat: generate implementation plan for user auth
implementor: feat: add OAuth authentication with Google provider
committer: chore: update dependencies to latest versions
```markdown

## Standard Agent Names

| Agent | Purpose |
| ------- | --------- |
| `planner` | Generated implementation plan |
| `implementor` | Implemented the solution |
| `classifier` | Classified the issue type |
| `reviewer` | Reviewed the changes |

## Commit Types

| Type | Description |
| ------ | ------------- |
| `feat` | New feature |
| `fix` | Bug fix |
| `chore` | Maintenance task |
| `docs` | Documentation changes |
| `refactor` | Code restructuring |
| `test` | Test additions or fixes |

## Input Variables

- **$1**: Agent name (planner, implementor, etc.)
- **$ARGUMENTS**: Context for commit message

## Rules

1. Keep description under 72 characters
2. Use present tense ("add" not "added")
3. Don't end with a period
4. Be specific about what changed

## Generation Process

1. Identify the agent from $1
2. Determine the commit type from context
3. Generate a concise description
4. Format as: `{agent}: {type}: {description}`

## Context

Agent: $1
Changes: $ARGUMENTS
