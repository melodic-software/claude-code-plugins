# Conditional Documentation Pattern

Load documentation only when conditions match to prevent context pollution.

## The Problem

Loading all documentation upfront:

- Wastes context window space
- Adds irrelevant information
- Distracts from the actual task
- Slows down agent reasoning

## The Solution

Define conditions for when each document should be loaded:

```markdown
- documentation_path
  - Conditions:
    - When working with X
    - When implementing Y
    - When troubleshooting Z
```markdown

## Implementation Format

### Conditional Docs File

Create a file that maps documentation to conditions:

```markdown
# Conditional Documentation

This helps determine what documentation to read based on the specific
changes you need to make in the codebase.

IMPORTANT: Only read documentation if any condition matches your task.

---

- README.md
  - Conditions:
    - When first understanding the project
    - When setting up the development environment
    - When learning project commands

- docs/api-reference.md
  - Conditions:
    - When working with API endpoints
    - When adding new routes
    - When modifying request/response formats

- docs/database-schema.md
  - Conditions:
    - When modifying database tables
    - When adding new models
    - When writing migrations

- docs/authentication.md
  - Conditions:
    - When working with login/logout
    - When implementing permissions
    - When debugging auth issues

- docs/testing-guide.md
  - Conditions:
    - When writing new tests
    - When test failures occur
    - When adding test fixtures
```markdown

## Integration with Planning Commands

Add conditional docs check to planning commands:

```markdown
## Relevant Documentation

Read `.claude/commands/conditional_docs.md` to check if your task
requires additional documentation. If your task matches any conditions
listed, include those documentation files.
```markdown

## Keeping Conditional Docs Updated

When documentation is added or changes:

1. Update the conditional docs file
2. Add new entries with appropriate conditions
3. Remove outdated entries
4. Review conditions for accuracy

### Auto-Update Pattern

After documentation generation:

```markdown
## Update Conditional Docs

If new documentation was created, add an entry to conditional_docs.md:

- {new_doc_path}
  - Conditions:
    - When working with {feature_area}
    - When implementing {related_functionality}
```markdown

## Benefits

### 1. Just-in-Time Loading

Documentation is loaded only when relevant:

```text
Task: "Add dark mode toggle"
Relevant: UI components docs, settings docs
Not loaded: API docs, database docs, auth docs
```markdown

### 2. Reduced Context Pollution

Agent focuses on what matters:

```text
Before: 50k tokens of "just in case" docs
After: 5k tokens of relevant docs
```markdown

### 3. Faster Agent Reasoning

Less to process = faster responses:

- Fewer variables to consider
- Clearer signal-to-noise ratio
- More focused reasoning

### 4. Self-Documenting System

The conditions document what each doc is for:

```text
database-schema.md
  - When modifying database tables ← This tells you what it covers
  - When adding new models
  - When writing migrations
```markdown

## Anti-Pattern: Load Everything

```markdown
## Documentation
Read all of these files before starting:
- README.md
- docs/api.md
- docs/database.md
- docs/auth.md
- docs/testing.md
- docs/deployment.md
- docs/architecture.md
...

## Task
Fix typo in footer
```markdown

This wastes tokens on irrelevant documentation.

## Best Practice: Condition Match

```markdown
## Task
Fix typo in footer

## Relevant Documentation
Check conditional_docs.md - UI/styling conditions match
→ Load only: docs/styling-guide.md
```markdown

Only relevant documentation is loaded.

## Related

- @minimum-context-principle.md - Why less context is better
- @one-agent-one-purpose.md - Focused agents need focused context
- @review-vs-test.md - Different tasks need different docs
