---
name: orient
description: "Read-only session orientation from durable + off-thread state — synthesize where we stand, what we are doing, and why, from the ledger files, handoff save-points, workflow checklists, running-retro ledgers, open PRs and work-items, and git state, not just the conversation. Complements the built-in /recap (conversation-only, auto-fires) by adding the durable state recap never sees. Use when: 'where were we', 'catch me up', 'orient me', 'get my bearings', 'what's the state', 'brief me', 'situation report', 'where do we stand', 'lay of the land'. Read-only: writes nothing, ends nothing, and does not verify freshness, recover off-thread work, or prescribe the next stage — it points at the sibling that does."
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: session
  summary: Read-only situation report from durable and off-thread state
---

## Context — gather first

Collect these with **individual** Bash calls, one command per call:

- Claude session id — `printenv CLAUDE_CODE_SESSION_ID`
- Current branch — `git branch --show-current`
- Recent commits — `git log --oneline -8`
- Working tree status — `git status --porcelain`, reading **at most the first 20 entries**

Treat any failure as an unknown value and carry on. These are gathered here rather than pre-computed
because a worktree-isolated agent refuses any command carrying a `$`-expansion, which made this skill
fail at load — keep `$`-expansion out of the pre-compute block (#1687).

# Orient

## Purpose

Answer, in one read-only briefing: **where do we stand, what are we doing,
and why.** The briefing draws on both the live conversation and the
durable, off-thread state a conversation does not hold — ledger files,
handoff save-points, workflow checklists, running-retro ledgers, open pull
requests and work-items, and git state. It orients; it changes nothing.

**Why this is not the built-in `/recap`.** `/recap` summarizes the
*conversation* and auto-fires when you return to an idle terminal. It never
reads the durable state on disk or the work running off this thread — and a
skill cannot invoke it (built-in commands other than a small allowlist are
not Skill-invocable). So this skill synthesizes the conversation summary
inline *and* adds the durable + off-thread layer `/recap` cannot see. Reach
for it when "what did the last session decide, and what is in flight right
now" matters, not just "what did we just say."

## What it reads (all read-only)

1. **The conversation** — the goal, the load-bearing decisions, and the
   direction established in this session. Synthesize these inline.
2. **Durable memory-tier state** — resolve locations through the plugin
   binding
   ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)),
   then read what exists, most-recent-first:
   - handoff save-points (`<memory_dir>/handoffs/`) — the last session's
     in-flight snapshot; its own brief names where the work stood;
   - the workflow checklist (`<memory_dir>/<slug>/`) — the stage ledger;
   - running-retro ledgers (`<memory_dir>/running-retros/`) — accumulated
     in-flight findings.
   This skill only reads these; it never writes them, so the write-time
   runtime guards do not apply. Degrade quietly when a location is absent.
3. **Repo + off-thread state** — the git context gathered above, plus, when
   the tools are present and degrading gracefully when they are not: open
   pull requests (`gh pr list` for the current branch / author), open
   work-items (the consumer's tracker seam), and a glance at work running
   off this thread — background tasks, monitors, subagents, and the other
   off-thread kinds
   ([`${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md`](${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md)).
   Report the off-thread work at a glance — do **not** inspect or recover
   it; that is `/session-flow:keep-going`.

## The briefing — four parts

Synthesize the reads into a short, current-state briefing:

- **Goal / why** — what we are trying to achieve and the reason, from the
  conversation and the handoff/ledger.
- **Where we stand** — the current state: branch, what is done versus
  pending, in-flight work — from the workflow checklist, handoff, and
  commits.
- **Decisions made** — the load-bearing decisions and their rationale so
  far, so they are not silently rediscovered or reversed.
- **Direction / what's live** — what is currently in motion: open PRs,
  off-thread work at a glance, and the intended thrust — *without*
  prescribing the next stage (that is `workflow`) or acting on it.

Ground every claim in a read this turn. Where the durable state and the
conversation disagree, surface the discrepancy rather than picking one —
and point at `/session-flow:reanchor` to verify which still holds.

## Boundaries — pick the right sibling

- **Built-in `/recap`** — conversation-only, auto-fires. This skill adds
  durable + off-thread state and runs on demand.
- **`/session-flow:workflow`** — "what stage is next." Orientation reports
  where we stand; it does not prescribe the next step.
- **`/session-flow:reanchor`** — "are my assumptions still true against
  live reality." Orientation synthesizes current state; it does not run a
  freshness/drift verification. When freshness is in doubt, it points here.
- **`/session-flow:keep-going`** — recovers and continues off-thread work.
  Orientation reports off-thread work at a glance; it recovers nothing.
- **`/session-flow:retro`** — "what did we learn" (end-of-session scoring +
  codify). Orientation extracts no learnings and scores nothing.
- **`/session-flow:handoff`** — writes a save-point and ends the session.
  Orientation writes nothing and ends nothing.

## What this skill does NOT do

- **Writes nothing** — no files, no memory, no `/clear`. It is a read-only
  briefing that leaves state untouched.
- **Does not verify freshness** — it reports what the durable state says;
  confirming those claims still hold is `/session-flow:reanchor`.
- **Does not recover off-thread work** — it names what is in flight;
  inspecting and resuming it is `/session-flow:keep-going`.
- **Does not prescribe the next stage** — that is `/session-flow:workflow`.
- **Does not score or codify** — that is `/session-flow:retro`.
- **Does not invoke the built-in `/recap`** — built-ins are not
  Skill-invocable; it synthesizes the conversation summary inline instead.

## Gotchas

- The durable state can be stale — a handoff or ledger describes the moment
  it was written, not now. Report it as "the handoff claims X," and route a
  freshness check to `/session-flow:reanchor` rather than asserting it as
  current fact.
- Optional tools (`gh`, a tracker CLI) may be absent or unauthenticated.
  Degrade to the state you can read and say what you could not reach; never
  block the briefing on a missing optional source.
- Off-thread work is reported at a glance only. The moment the ask becomes
  "resume it" or "is it stuck," that is `/session-flow:keep-going`, not this
  skill.
