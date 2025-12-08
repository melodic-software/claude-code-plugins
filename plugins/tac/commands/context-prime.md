---
description: Load task-specific context dynamically based on task type (bug, feature, review, chore, research)
argument-hint: [task-type]
---

# Context Prime

Load task-specific context dynamically based on task type.

## Arguments

- `$ARGUMENTS`: Task type (bug, feature, review, chore, research) or custom description

## Instructions

You are loading task-specific context to prime the agent for focused work.

### Step 1: Determine Task Type

Parse `$ARGUMENTS` to determine task type:

| Type | Context Focus |
| ------ | --------------- |
| bug | Recent commits, test files, error patterns |
| feature | Architecture, related modules, API patterns |
| review | Style guide, test patterns, changed files |
| chore | Project structure, tooling, configs |
| research | Documentation, external resources, examples |
| (custom) | Infer appropriate context from description |

### Step 2: Execute Discovery

**For all types - Run:**

```bash
git status
git ls-files | head -50
```

**Type-specific discovery:**

**bug:**

```bash
git log --oneline -10
git diff HEAD~5 --stat
```

**feature:**

```bash
ls -la src/
ls -la lib/
```

**review:**

```bash
git diff --stat
git log --oneline -5
```

**chore:**

```bash
ls -la
cat package.json | head -20  # or equivalent manifest
```

**research:**

```bash
ls -la docs/ 2>/dev/null | | echo "No docs directory"
ls -la ai_docs/ 2>/dev/null | | echo "No ai_docs directory"
```

### Step 3: Load Essential Files

**For all types - Read:**

- README.md (if exists)

**Type-specific reads:**

**bug:**

- Recent test files related to area
- Configuration files

**feature:**

- Architecture documentation
- Similar feature implementations

**review:**

- Style guide or linting config
- Test patterns

**chore:**

- Tooling documentation
- Build/deploy configs

**research:**

- Existing documentation
- Reference materials

### Step 4: Report Understanding

## Output

Summarize loaded context:

```markdown
## Context Primed: [Type]

**Task Type:** [bug/feature/review/chore/research]
**Files Loaded:** [count]

### Project State
- Branch: [current branch]
- Status: [clean/dirty]
- Recent changes: [summary]

### Loaded Context
- [File 1]: [brief description]
- [File 2]: [brief description]

### Ready For
[What this priming prepares you for]

### Context Efficiency
This priming loaded ~[X] tokens of task-specific context.
Remaining capacity: [estimate]
```

## Notes

- Priming loads fresh, relevant context for the task at hand
- Prefer priming over static CLAUDE.md for task-specific work
- See @context-priming-patterns.md for pattern details
- See @rd-framework.md for reduce and delegate strategies
