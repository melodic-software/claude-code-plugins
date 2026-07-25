---
name: blindspot
description: "Surface the USER's unknown-unknowns before they work in unfamiliar territory — an unfamiliar codebase area OR an unfamiliar domain vocabulary — and coach a sharper prompt. Scans for gaps the user's framing missed, emits one blindspot card per gap (the gap, why it matters here, a copyable prompt-fix line), then assembles the fixes into one improved implementation prompt. Use when: 'what am I missing', 'find my blindspots', 'what do I not know here', 'sharpen this prompt', 'I am new to this area', or about to work somewhere you do not know well and the goal is a better prompt — not the codebase handoff artifact /discovery:explore produces."
argument-hint: "[area-or-domain] (e.g., /discovery:blindspot geofencing, /discovery:blindspot payments module, /discovery:blindspot <domain-vocabulary>)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

These values orient this session only; resolve files against the project root while working.

## Purpose

Every mode of `/discovery:explore` builds the AGENT's local knowledge and hands off an `EXPLORE.md`
artifact. Blindspot mode builds the USER's knowledge and hands off a better prompt — a different
audience and a different deliverable, which is why it is its own skill.

Run it when the user is about to work in territory they don't know — an unfamiliar codebase area OR
an unfamiliar domain vocabulary — and the goal is to surface what their framing didn't account for
so they can write a sharper implementation prompt. The output is calibrated to the user's disclosed
starting point, not to a fixed depth.

Local counterpart discipline to `/discovery:explore` (what IS in the codebase) and `/discovery:research`
(what SHOULD BE from external sources): blindspot borrows from both lanes but serves the user's
understanding rather than the agent's.

## Workflow

1. **Intake** — ask the user's starting point first (one question). Blindspot output calibrates to
   that disclosure — what they already know bounds which gaps are worth surfacing.
2. **Scan** — two lanes, chosen by what is unfamiliar:
   - **Codebase lane** — read the target area (the codebase-reading, git-history, and project-structure
     dimensions of [`${CLAUDE_PLUGIN_ROOT}/skills/explore/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/SKILL.md))
     looking specifically for things the user's framing missed: existing patterns they'd duplicate,
     constraints they'd violate, historical decisions they'd re-litigate, adjacent code their change
     would break.
   - **Domain lane** — build a lightweight vocabulary ladder grounded in sources fetched this session
     (repo files, official docs) — never bare training recall.
3. **Output — blindspot cards.** One card per blindspot: the gap, why it matters here, and a copyable
   prompt-fix line. Close by assembling the fixes into ONE improved implementation prompt the user can
   run next.
4. **Escalate when depth warranted** — a domain too deep for a lightweight ladder gets a recommendation
   to run proper external research (`/discovery:research`) or whatever structured-learning capability
   the environment provides.

## Output format

Present each blindspot as a card:

- **Gap** — the specific thing the user's current framing did not account for.
- **Why it matters here** — the concrete consequence in this codebase or domain, not a generic caution.
- **Prompt-fix** — a single copyable line the user can drop into their prompt to close the gap.

Then assemble every prompt-fix into ONE improved implementation prompt, wrapped in clear
copy-start / copy-end markers so the exact text to reuse is unambiguous.

This skill does NOT write `EXPLORE.md` — its deliverable is the user's understanding plus the improved
prompt. When the scan's findings also serve as stage-1 codebase exploration, offer to hand off to
`/discovery:explore` to persist the `EXPLORE.md` artifact rather than
duplicating that responsibility here.

## Gotchas

- **Presenting training recall as domain fact** — the domain lane grounds its vocabulary ladder in
  sources fetched this session (repo files, official docs). Bare recall is the failure mode this
  skill exists to avoid, not commit.
- **Surfacing the agent's gaps instead of the user's** — cards name what the USER's framing missed,
  calibrated to their intake disclosure, not a generic audit of the area.
- **Generic cautions in "why it matters"** — each card's consequence is concrete to this codebase or
  domain; a caution that would read the same in any repo is not a blindspot.
- **Writing an artifact by reflex** — no `EXPLORE.md` unless the user opts into the explore handoff.

## What this skill does NOT do

- **Does not produce the `EXPLORE.md` handoff** — that is `/discovery:explore`. Hand off to it when the
  findings double as stage-1 exploration.
- **Does not make changes** — it surfaces blindspots and coaches a prompt. Execution is a separate step.
- **Does not run open-ended external research** — the domain lane fetches official docs to ground a
  lightweight vocabulary ladder; anything deeper routes to `/discovery:research`.
