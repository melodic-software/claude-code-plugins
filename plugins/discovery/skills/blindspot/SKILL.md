---
description: "Surface the USER's unknown-unknowns before they work in unfamiliar territory and coach a sharper prompt. Use when: 'what am I missing', 'find my blindspots', 'what do I not know here', 'sharpen this prompt', 'I am new to this area', or about to work in an unfamiliar area and the goal is a better prompt, not the codebase handoff /discovery:explore produces."
argument-hint: "[area-or-domain]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: explore
  summary: Surface your unknown-unknowns and sharpen the prompt before unfamiliar work
---

**Arguments.** `[area-or-domain]`. e.g., /discovery:blindspot geofencing, /discovery:blindspot payments module, /discovery:blindspot <domain-vocabulary>

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Project root, `git rev-parse --show-toplevel`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

These values orient this session only; resolve files against the project root while working.

## Workflow

This skill builds the USER's knowledge, not the agent's: the deliverable is the user's
understanding plus one improved implementation prompt, calibrated to their disclosed starting
point rather than a fixed depth.

1. **Intake**. Ask the user's starting point first (one question). What they already know bounds
   which gaps are worth surfacing.
2. **Scan**. Two lanes, chosen by what is unfamiliar:
   - **Codebase lane**. Read the target area (the codebase-reading, git-history, and project-structure
     dimensions in [`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/workflow.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/workflow.md))
     looking specifically for things the user's framing missed: existing patterns they'd duplicate,
     constraints they'd violate, historical decisions they'd re-litigate, adjacent code their change
     would break.
   - **Domain lane**. Build a lightweight vocabulary ladder grounded in sources fetched this session
     (repo files, official docs), never bare training recall. Right after the ladder, add a block of
     the quality axes experts judge the work by, with a worked good-vs-bad example per axis, each
     grounded in a source fetched this session. The axes are their own block ahead of the cards, not
     a card type. Each axis becomes a prompt-fix line in the improved prompt, which the user keeps or
     deletes like any other fix. A criterion the user's framing never named may also appear as a
     **Missing concept** card.
3. **Output**. Blindspot cards, then ONE improved implementation prompt assembled from their
   prompt-fix lines (Output format below).
4. **Escalate when depth warranted**. A domain too deep for a lightweight ladder gets a
   recommendation to learn it in a structured way: `/education:teach topic <domain>` when it is
   among the available skills, otherwise proper external research, `/discovery:research` invoked
   via the Skill tool.

## Output format

Present each blindspot as a card:

- **Type**, one of four: **Landmine** (the change would break something non-obvious), **History**
  (a constraint whose reason the code no longer shows), **Convention** (an unwritten team rule the
  work must follow), or **Missing concept** (a domain idea the user's framing never named).
- **Gap**, the specific thing the user's current framing did not account for.
- **Why it matters here**, the concrete consequence in this codebase or domain, not a generic caution.
- **Prompt-fix**, a single copyable line the user can drop into their prompt to close the gap.

Then assemble every prompt-fix into ONE improved implementation prompt, wrapped in clear
copy-start / copy-end markers so the exact text to reuse is unambiguous.

End with one scan-scope disclosure line: which lane(s) ran and what was and was not scanned (areas
read, sources fetched). One line, not a methodology dump.

For a long card list, offer an interactive view (cards filterable by type, a tick for each that was news, a copy-out of the reaction). The page is never written beside the cards, which stay the record. Build it only with `${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs`, never hand-written; the publish destination comes from the `medium` cascade key. Procedure and data shape: [`${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md`](${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md).

This skill makes no changes and runs no open-ended external research: the domain lane fetches
official docs only to ground the ladder and quality axes, and anything deeper routes to
`/discovery:research`, invoked via the Skill tool. It does NOT write `EXPLORE.md`. When the scan's findings also serve
as stage-1 codebase exploration, offer to hand off to `/discovery:explore`, invoked via the Skill
tool, to persist the `EXPLORE.md` artifact.

## Next

- The scan doubles as stage-1 codebase exploration: `/discovery:explore <area>`.
- The prompt is sharpened and ready to scope: `/planning:interview`.
- Unsure where this leaves the work, or arrived mid-flow: `/session-flow:workflow`.

## Gotchas

- **Presenting training recall as domain fact**. The domain lane grounds its vocabulary ladder
  and quality axes, good-vs-bad examples included, in sources fetched this session (repo files,
  official docs).
- **Surfacing the agent's gaps instead of the user's**. Cards name what the USER's framing missed,
  calibrated to their intake disclosure, not a generic audit of the area.
- **Generic cautions in "why it matters"**. Each card's consequence is concrete to this codebase or
  domain; a caution that would read the same in any repo is not a blindspot.
- **Writing an artifact by reflex**. No `EXPLORE.md` unless the user opts into the explore handoff.
