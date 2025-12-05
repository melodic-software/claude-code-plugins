# Context Priming Patterns

Context priming uses dynamic, task-specific context loading instead of static always-on memory files. This keeps agents focused and context fresh.

## Static Memory vs Dynamic Priming

| Approach | Pros | Cons |
| ---------- | ------ | ------ |
| **CLAUDE.md** | Always available, automatic | Grows over time, becomes bloated |
| **Priming Commands** | Task-specific, controllable | Requires explicit invocation |

## The Problem with Always-On Context

```text
Day 1:   CLAUDE.md = 500 tokens (clean)
Day 30:  CLAUDE.md = 2,000 tokens (growing)
Day 90:  CLAUDE.md = 5,000 tokens (bloated)
Day 180: CLAUDE.md = 10,000+ tokens (unmaintainable)
```markdown

Always-on memory files:

- Only grow, never shrink
- Accumulate contradictions
- Include outdated guidance
- Can't adapt to task type
- Consume tokens every instance

## The Priming Solution

```text
/prime      -> Base codebase context
/prime_bug  -> Bug-fixing context
/prime_feat -> Feature development context
/prime_cc   -> Claude Code specific context
```markdown

Each priming command loads exactly what's needed for that task type.

## Priming Command Pattern

A priming command has three sections:

```markdown
# Prime

## Run
Execute discovery commands to understand current state.

## Read
Load specific files relevant to the task type.

## Report
Summarize understanding for the agent.
```markdown

### Example: /prime (Base Context)

```markdown
## Run
git ls-files

## Read
README.md

## Report
Summarize your understanding of the codebase.
```markdown

### Example: /prime_bug (Bug Context)

```markdown
## Run
git log --oneline -10
git status

## Read
README.md
CHANGELOG.md

## Report
Summarize recent changes and current state.
Focus on potential bug sources.
```markdown

### Example: /prime_cc (Claude Code Context)

```markdown
## Run
ls -la .claude/

## Read
.claude/settings.json
CLAUDE.md

## Report
Summarize Claude Code configuration.
Identify available commands, hooks, agents.
```markdown

## Building Your Priming Commands

### Step 1: Identify Task Types

What kinds of work do you do?

- Bug fixes
- New features
- Code reviews
- Documentation
- Refactoring
- Testing

### Step 2: Determine Context Needs

For each task type, what context is essential?

| Task Type | Essential Context |
| ----------- | ------------------- |
| Bug fix | Recent commits, test files, error patterns |
| Feature | Architecture docs, related modules, API patterns |
| Review | Style guide, test patterns, PR diff |
| Docs | Existing docs, API surface, examples |

### Step 3: Create Priming Commands

For each task type, create a command that:

1. Runs discovery (git status, ls, etc.)
2. Reads essential files
3. Reports understanding summary

## The CLAUDE.md Minimization Pattern

With priming commands, CLAUDE.md becomes minimal:

```markdown
# Project Name

## Context
Brief project description. One sentence.

## Tooling
- Language: TypeScript
- Runtime: Bun
- Test: vitest

## Key Commands
- `bun test` - Run tests
- `bun build` - Build project

## Development
1. Keep functions under 50 lines
2. Write tests first
```markdown

Everything else delegates to priming commands.

## The Three-Tier Memory Strategy

```text
Tier 1: CLAUDE.md (minimal, always loaded)
        - Just essentials, under 2KB
        - Tooling, key commands, critical rules

Tier 2: /prime commands (task-specific, on-demand)
        - Loaded at task start
        - Task-type context

Tier 3: File reads (just-in-time, as needed)
        - Loaded during execution
        - Specific to current work
```yaml

## The Guiding Question

Before adding to CLAUDE.md, ask:

> "Does every agent, for every task, need this information?"

If no, move it to:

- A priming command (task-type specific)
- An on-demand file read (specific file)
- Documentation (reference material)

## Context Priming vs Context Bundles

| Pattern | Purpose | When to Use |
| --------- | --------- | ------------- |
| Priming | Load task-type context | Starting new work |
| Bundles | Reload previous session | Continuing previous work |

Priming loads fresh, relevant context.
Bundles restore previous session state.

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| Everything in CLAUDE.md | Bloat, rot | Minimize, delegate |
| No priming commands | Same context for all | Create task-specific primes |
| Giant priming commands | Defeats purpose | Keep focused |
| Never using priming | Context pollution | Prime at task start |

## Key Quote

> "Use context priming over CLAUDE.md or similar auto-loading memory files. Context priming uses dedicated reusable prompts to set up your agent's initial context specifically for the task type at hand."

---

**Cross-References:**

- @rd-framework.md - Reduce and Delegate strategies
- @context-layers.md - Understanding what loads into context
- @minimum-context-principle.md - Include only what's necessary
