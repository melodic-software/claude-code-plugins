---
name: handoff
description: "Write a mid-session save-point for /clear-and-resume — a durable handoff file (default) or a copy-paste resume prompt when follow-ups are small. Use when: 'handoff', 'save state', 'checkpoint this', 'pause', 'come back later', context is heavy, or quality is degrading. For delegating the continuation to a background agent, use the sibling continue-in-background skill."
argument-hint: "[file|prompt] [topic] (e.g., /handoff, /handoff prompt, /handoff file phase-3)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`
Uncommitted changes: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

Context bloat is expensive and quality degrades as context rots. When a task has room left but
context is heavy, capture a save-point — a handoff document, or just a copy-paste resume prompt when
follow-ups are small — and `/clear`.

Based on the canonical pattern Anthropic recommends for the `/clear` workflow: put the rest of the
plan in a handoff file; explain what you tried, what worked, and what didn't, so the next agent with
fresh context can load that file and nothing else. The save-point captures a *snapshot* of in-flight
state — including what was tried and ruled out — so the next session doesn't waste effort
rediscovering dead ends.

This skill delivers the save-point for a MANUAL resume: the user `/clear`s and pastes the resume
prompt themselves. To hand the resume prompt to a fresh background agent that continues the task
now, use the sibling `/session-flow:continue-in-background` skill instead — same save-point engine,
different delivery.

## Arguments

`$ARGUMENTS` carries `[file|prompt] [topic]` — both optional and positional:

- **Method** (`file` | `prompt`) — recognized ONLY as the first token. `file` forces the full
  durable handoff; `prompt` forces prompt-only. Omitted → auto-detect (engine doc, "Choosing the
  path").
- **Topic** — short kebab slug for the filename. When the first token is not a method keyword it IS
  the topic (`/handoff phase-3`); with a method present it is the second token. Omitted → inferred
  from context.

## Hard rule — handoff ALWAYS terminates current execution

**The whole point of `/handoff` is `/clear` + fresh-session resume.** The skill produces the
save-point, THEN STOPS. It does NOT keep executing the underlying task in the current session; that
defeats the purpose. STOP is the default and near-universal outcome — NEVER unlocked by the user
having listed multiple steps, nor by the remaining work being "small".

**Mandatory STOP gate (walk every box):**

- [ ] Path chosen (full vs prompt-only) per the engine doc
- [ ] Copy/paste resume prompt emitted between two dashed rails (engine doc, "Emit the copy/paste
  resume prompt")
- [ ] `/clear`-then-paste instruction surfaced to the user
- [ ] **STOP.** No further work items, no next phase, no follow-on skill, no commit/push. The
  session ends as far as the task is concerned

**NOT authorization to continue (these all STOP):**

- A multi-step pipeline naming `/handoff` (e.g. "handoff, then verify, then PR") → the listed steps
  run in the FRESH session AFTER `/clear`. Naming `/handoff` names a `/clear` boundary, not a waiver
- "do all of it" → authorizes executing the phases across the session chain, but each `/handoff`
  between them still enforces its `/clear` boundary (that is WHY the handoffs get written)
- A standalone user-invoked `/handoff` → always STOP, regardless of surrounding instructions

The only exception: the user's prior turn used explicit stay-in-session language about handoffs
specifically (e.g. "don't `/clear` between phases, keep going").

## When to invoke

- Mid-task, context heavy (check `/context` output or user report)
- Quality degrading (context rot) — responses drifting, repeating, or looping
- About to pause for hours/overnight; want a clean resume
- About to switch to a different task; this one isn't done
- Last turn had an unexpected compaction
- Sharing state with another session or machine

Going AFK but the work should keep moving → that is the sibling
`/session-flow:continue-in-background` skill's job, and only on the user's explicit request.

## Fork beats compaction when the window is deep

Two ways to keep going past a heavy context: fork (handoff file + `/clear` + fresh session) or
continue in place over a compacted history. Compaction suits an intentional break between phases
while the window is still mostly fresh — the summarized turns were genuinely disposable. Once the
session has consumed enough of its context window that reasoning quality degrades — roughly beyond
the final third of the window — fork instead: a handoff file carries forward exactly the state that
matters, chosen deliberately, while a compaction summary carries forward whatever the summarizer
happened to keep, and the degradation that prompted the move rides along into the continued
session. Judge the threshold by window position and response quality, never by a fixed token count
— it shifts with model and configuration.

## Produce the save-point

The save-point machinery — destination resolution, locating the position, full-vs-prompt-only
choice, the mandatory redaction pass, the handoff-file write, and the rails resume prompt — lives
in the shared engine doc
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md).
Walk it top to bottom; do not restate or improvise any of its steps.

## Delivery: `/clear`-then-paste

This skill's delivery step is the engine's default exit: the rails resume prompt with the
"`/clear`, then copy everything between the dashed lines" instruction above the top rail. The user
types `/clear` and pastes; nothing is launched on their behalf.

## Post-write enforcement checklist

Tick each item in the response so the user can verify the exit shape. Missing any tick = handoff
incomplete. Known failure patterns live in `context/gotchas.md` — load on demand when a step feels
ambiguous.

**Full path:**

- [ ] Position located + next stage named (fresh reads this turn)
- [ ] Handoff file written to the handoff location (self-ignore guard verified first) with
  frontmatter per the engine's structure doc (`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`)
- [ ] `previous_handoff` + `previous_session_id` present IF this session continued a prior
  handoff's task (chain continuity per the same structure doc); omitted otherwise — including when
  the directory holds only unrelated-task handoffs
- [ ] All eight body sections present
- [ ] Redaction pass swept the file AND the prompt (secrets/tokens/credentials/PII replaced with
  shape markers)
- [ ] TaskList snapshot + Reconstitute sections present (OR explicit "exception: 0 active tasks")
- [ ] Resume prompt emitted between dashed rails, `@`-referencing the file; copy instruction above
  the top rail; `/goal` first line if a goal is active
- [ ] **EXECUTION STOPS HERE**

**Prompt-only path:**

- [ ] Prompt-only justified (all auto-detect criteria hold, OR `prompt` explicitly passed)
- [ ] Redaction pass swept the prompt (secrets/tokens/credentials/PII replaced with shape markers)
- [ ] Self-contained resume prompt between dashed rails — remaining-work bullets inline
- [ ] Copy instruction above the rails; `/goal` first line if a goal is active
- [ ] **EXECUTION STOPS HERE** — "small enough" means the prompt captures the work, NOT "small
  enough to skip `/clear` and finish in-session"

## What this skill does NOT do

- **Does not commit** — handoff docs are durable task state, not source code. Commit ready code
  changes separately; describe uncommitted work in "Progress"
- **Does not invoke `/clear`** — the user types `/clear`. The skill produces the save-point, emits
  the resume prompt, and stops
- **Does not launch a background agent** — background delegation is the sibling
  `/session-flow:continue-in-background` skill, and it fires only on the user's explicit request
- **Does not continue executing the underlying task** — per the hard rule above. Prompt-only does
  NOT relax this
- **Does not replace a contract or plan** — it captures in-flight state at any point
- **Does not summarize the whole conversation** — task-relevant state only
