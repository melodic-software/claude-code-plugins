# Quick Mode — Abbreviated Retrospective

Lightweight retrospective when the full 5-phase analysis isn't appropriate. Use when context is
limited (post-compaction, short session), or the user explicitly requests a quick pass.

## When to use

- Context window >75% used or compaction has occurred
- Short session (single task, <30 minutes)
- User says "quick retro" or "abbreviated retro"
- Post-merge when a full retro would exceed the remaining context budget

## Process

### 1. Skip metrics extraction

Do NOT run the parser. Use conversation context only.

### 2. Behavioral quick-check

Assess against the staged workflow as a checklist — not full dimensional analysis:

| Stage | Done? | Note |
|------|-------|------|
| 1. Explore | Yes/No/Partial | (one line) |
| 2. Research | Yes/No/Partial | |
| 3. Plan | Yes/No/Partial/N/A | |
| 4. Implement | Yes/No/Partial | |
| 5. Test | Yes/No/Partial/N/A | |
| 6. Review | Yes/No/Partial | |
| 7. Verify | Yes/No/Partial | |
| 8. Retro | In progress | (this) |

### 3. Top findings (max 3)

Only errors, regressions, or significant behavioral gaps — skip minor issues.

### 4. Recommendations (max 3)

Highest-priority only, same format as session mode Phase 3 but capped.

### 5. Quick score

> **Session score: X/10** — (one sentence justification)

Append to the score history (`${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md`) using the session-
mode format.

### 6. Feedback regression spot-check

If auto-memory exists, read up to 10 recent `feedback_*.md` files (not all — budget constraint) and
flag any regression prominently.

## What this mode does NOT do

- No parser run (no Phase 1), no full 5-dimension analysis
- No skill/follow-up candidate generation (unless something jumps out)
- No interactive Phase 4 approval gate — present recommendations and execute approved items
  directly

It's fast: scan, flag, score, move on.
