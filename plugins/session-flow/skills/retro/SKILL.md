---
name: retro
description: "Run a structured session retrospective: extract transcript metrics, assess quality across five dimensions, check feedback-memory regressions, and codify learnings durably. Use when: 'retro', 'retrospective', 'what did we learn', 'how did I do', 'codify learnings', 'show trends', or at end of session; modes: session (default), codify, trends, quick."
argument-hint: "[mode] (e.g., /retro, /retro session, /retro codify, /retro trends, /retro quick)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`

## Repository context — gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch — `git branch --show-current`
- Recent commits — `git log --oneline -5`
- Working tree status — `git status --porcelain`
- Changed files (staged+unstaged) — `git diff --name-only HEAD`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. These moved
out of pre-compute in #1619 — the harness composes the block into one shell invocation and a
worktree-isolated agent refuses a git-bearing compound command; do not fold them back.

## Purpose

The self-improvement loop. Answers: "What happened, what did we learn, and how do we prevent the
same mistakes next time?" Every other workflow stage is about the current task; this skill is about
the next task — and every task after that.

**Three concepts this skill enforces:**

1. **Analyze** — examine what happened with evidence (transcript metrics, conversation context,
   feedback regressions)
2. **Identify** — find errors, behavioral adjustments, process improvements, and skill/tool
   candidates
3. **Codify** — persist learnings durably (the consuming repo's instruction files and rules, or
   Claude Code auto-memory for contributor-specific facts)

**What this skill is NOT:** not a code review (design judgment on current work), not outcome
verification (does the change match intent), and not Claude Code's built-in `/insights`
(cross-session usage analytics) — this is structured quality analysis with codification.

## Paths

Resolve at runtime — never hardcode machine-specific paths:

- **Session data root** — `~/.claude/projects/<project-slug>/`, where `<project-slug>` is the
  project's absolute path with every character outside `[A-Za-z0-9]` replaced by `-`:

  ```bash
  PROJECT_SLUG=$(pwd -W 2>/dev/null || pwd)          # Windows drive form when available
  PROJECT_SLUG=$(printf '%s' "$PROJECT_SLUG" | sed 's/[^A-Za-z0-9]/-/g')
  SESSION_DATA_DIR="$HOME/.claude/projects/$PROJECT_SLUG"
  ```

  Verify the directory exists before use; if the computed slug misses, find it by locating the
  current session's JSONL: `ls "$HOME/.claude/projects"/*/"${CLAUDE_CODE_SESSION_ID}.jsonl"`.
- Transcript: `<SESSION_DATA_DIR>/<session-id>.jsonl`; subagents:
  `<SESSION_DATA_DIR>/<session-id>/subagents/`
- **Auto-memory** (feedback regression check): `<SESSION_DATA_DIR>/memory/` — present only when the
  consumer uses Claude Code auto-memory; degrade gracefully when absent
- **Score history** (plugin state): `${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md` — survives
  plugin updates, never lands in the consumer's repo
- Parser: `${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse_transcript.py` (stdlib-only,
  Python 3.10+)

## Step 0: Detect mode

| Signal | Mode | Context file |
|--------|------|-------------|
| End of session, bare `/retro`, post-merge | **session** | `context/session.md` — full 5-phase analysis |
| "codify", "save learnings", mid-session learning | **codify** | `context/codify.md` — targeted codification only |
| "trends", "scores", "how am I doing" | **trends** | `context/trends.md` — cross-session score history |
| "quick retro", short session, limited context | **quick** | `context/quick.md` — abbreviated pass |

If `$ARGUMENTS` specifies a mode, use it. Otherwise infer from context; when context is >75% used
or compaction has occurred, prefer `quick`; ambiguous → `session`. Read the mode's context file
before proceeding.

## Step 1: Execute the mode

Follow the selected context file. Each mode has its own phases, outputs, and interactive
checkpoints.

## Step 2: Handoff

After the retrospective:

| Condition | Suggestion |
|-----------|-----------|
| End-of-session, retro complete | Suggest any wrap-up steps the consuming repo defines |
| Codify mode, learnings saved | Return to the task at hand |
| Trends mode, analysis presented | Suggest focus areas for next session |
| Session mode, follow-ups queued | Suggest filing them in the consumer's work-item tracker |

## Multi-session awareness

When the sibling `handoff` skill's save-points exist (the resolved `<memory_dir>/handoffs/`,
default `.work/handoffs/`; or the consuming repo's documented location), the retro spans the
whole session CHAIN, not just the current session: the
parser's `--chain-from` walks `previous_handoff` frontmatter pointers
backwards from the newest handoff file and aggregates metrics across every chained transcript. See
`context/session.md` Phase 1.

## What this skill does NOT do

- **Does not run builds or tests** — that's the consuming repo's verify stage
- **Does not review code quality** — that's its review stage
- **Does not write scores or reports into the consumer's repo** — plugin state stays in
  `${CLAUDE_PLUGIN_DATA}`; only user-approved codifications (rule edits, memory entries) land
  outside it
- **Does not read a consumer-supplied scoring rubric** — the five dimensions are fixed plugin
  identity, not consumer config, and there is no seam to swap them. What adapts is what each
  dimension scores *against* (your repo's conventions, session-type calibration), never the
  dimensions themselves.

## Gotchas

- **Run all phases by default** in session mode — skip metrics only when the parser fails or the
  user asks
- **Always include skill-candidate and follow-up-candidate analysis** — even when the conclusion is
  "no candidates this session"
- **Codify follows the workflow too** — adding a bullet to a rules file requires verification, not
  just pasting
- **Phase 4 is an interactive checkpoint** — never persist codifications without explicit user
  approval
