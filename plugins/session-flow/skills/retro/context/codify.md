# Codify Mode — Targeted Learning Capture

Persist specific learnings from the current session without running the full retrospective. Use
mid-session when a valuable learning emerges, or any time something should be saved before it is
lost to context compaction.

## When to use

- A gotcha was discovered that future sessions need to know
- A convention was established through implementation that should be documented
- A correction happened that should prevent the same mistake next time
- Tool/library behavior was verified that should be recorded
- The user says "remember this" or "save this learning"

## Process

### 1. Identify what to codify

Scan the recent conversation for learnings:

| Category | Target | Example |
|----------|--------|---------|
| Behavioral correction | Auto-memory feedback entry | "Always verify API versions before using features" |
| Convention established | The repo's rules file or `CLAUDE.md` | "This repo uses pattern X, not Y" |
| External reference | Auto-memory reference entry | "Framework testing docs at <url>" |
| Project context | Auto-memory project entry | "Middleware rewrite driven by compliance, not tech debt" |
| Tool/API discovery | The repo's rules gotcha section | "Flag Z breaks the test runner" |

### 2. Apply the placement decision tree

1. Would another contributor on a fresh clone need this? → **project** (the repo's tracked
   instruction files)
2. Does it protect the accuracy of a git-tracked artifact? → **project** (in the artifact)
3. Is it about how this specific user wants the agent to behave? → **personal** (feedback memory)
4. Is it about the user's role or expertise? → **personal** (user memory)
5. Is it about ongoing work status? → **personal** (project memory)
6. Is it a pointer to external information? → **personal** (reference memory)

When in doubt, prefer project scope — a tracked rule is reviewable and portable; a personal memory
is neither.

### 3. Verify before persisting

Every codification is itself a technical claim:

- **Memory entries**: verify content is accurate against current codebase state; update an
  existing entry rather than duplicating; delete entries this session's evidence falsified
- **Rules / CLAUDE.md edits**: verify the claim (even if observed in conversation), cross-reference
  existing content for consistency and duplication

### 4. Present and confirm

Present proposed codifications grouped by scope (personal vs project) as tables with a one-line
content summary each. Ask for approval before executing. Then return to the current work.

## What this mode does NOT do

- No transcript metrics, no behavioral assessment or scoring
- No feedback regression history check
- No skill/follow-up candidate generation
- No health score

It's surgical: identify, verify, persist, return.
