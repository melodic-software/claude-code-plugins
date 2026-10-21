---
description: "Read-only orientation from durable state: where the session stands and why, from ledgers, handoff save-points, workflow checklists, running-retro ledgers, open PRs and work items, and git, which the built-in /recap never sees. Use when: 'where were we', 'catch me up', 'orient me', 'get my bearings', 'what's the state', 'brief me', 'situation report', 'where do we stand', 'lay of the land'. Writes nothing; freshness checks, recovery, and the next stage belong to sibling skills. Skip: what past sessions tried on a topic is /session-flow:recall."
user-invocable: true
disable-model-invocation: false
argument-hint: "[catch-up]"
metadata:
  workflow-stage: session
  summary: Read-only situation report from durable and off-thread state
---

## Context. Gather first

Take `session-id`, `branch`, `status`, and `recent-commits` at **`-8`**. Probe commands, the
one-command-per-call and treat-failure-as-unknown rules, and the `$`-expansion rationale for
gathering at run time rather than pre-computing:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

# Orient

## Purpose

Answer, in one read-only briefing: **where do we stand, what are we doing,
and why.** The briefing draws on both the live conversation and the
durable, off-thread state a conversation does not hold. Ledger files,
handoff save-points, workflow checklists, running-retro ledgers, open pull
requests and work-items, and git state. It orients; it changes nothing.

**Not the built-in `/recap`.** `/recap` summarizes only the *conversation*,
never the durable state on disk or the work running off this thread, and this
skill does not invoke it. So this skill synthesizes the conversation summary
inline *and* adds the durable + off-thread layer `/recap` cannot see. Reach
for it when "what did the last session decide, and what is in flight right
now" matters, not just "what did we just say." The verification records
(pointer, as-of date, recheck trigger) live in
[reference/native-recap.md](reference/native-recap.md).

## What it reads (all read-only)

1. **The conversation**, the goal, the load-bearing decisions, and the
   direction established in this session. Synthesize these inline.
2. **Durable memory-tier state**. Read what exists, most-recent-first:
   - handoff save-points (`<memory_dir>/handoffs/`), the last session's
     in-flight snapshot; its own brief names where the work stood;
   - the workflow checklist (`<memory_dir>/<slug>/`), the stage ledger;
   - running-retro ledgers (`<memory_dir>/running-retros/`), accumulated
     in-flight findings.
   This skill only reads these; it never writes them, so the write-time
   runtime guards do not apply. Degrade quietly when a location is absent.
3. **Repo + off-thread state**, the git context gathered above, plus, when
   the tools are present and degrading gracefully when they are not: open
   pull requests (`gh pr list` for the current branch / author), open
   work-items (the consumer's tracker seam), and a glance at work running
   off this thread. Background tasks, monitors, subagents, and the other
   off-thread kinds
   ([`${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md`](${CLAUDE_PLUGIN_ROOT}/reference/off-thread-work.md)).
   Report the off-thread work at a glance. Do **not** inspect or recover
   it; that is `/session-flow:keep-going`.

## The briefing. Four parts

Synthesize the reads into a short, current-state briefing:

- **Goal / why**. What we are trying to achieve and the reason, from the
  conversation and the handoff/ledger.
- **Where we stand**, the current state: branch, what is done versus
  pending, in-flight work, from the workflow checklist, handoff, and
  commits.
- **Decisions made**, the load-bearing decisions and their rationale so
  far, so they are not silently rediscovered or reversed.
- **Direction / what's live**, what is currently in motion: open PRs,
  off-thread work at a glance, and the intended thrust, *without*
  prescribing the next stage (that is `workflow`) or acting on it.

Ground every claim in a read this turn. Where the durable state and the
conversation disagree, surface the discrepancy rather than picking one,
and point at `/session-flow:reanchor` to verify which still holds.

## Catch-up scope. `/session-flow:orient catch-up`

The four-part briefing above stays the default. This scope runs **only** on the explicit
argument `catch-up`; a bare "catch me up" keeps the four-part briefing. It answers "what
happened since my last message, and what needs me", still read-only.

**Word cap.** The whole reply stays within `${user_config.orient_catch_up_word_cap}` words,
visuals excluded. A value still reading `${user_config.…}`, or empty, is unset: the cap is 250.
A value below 150 is treated as 150.

**Anchor.** The user's last message they wrote themselves. Notifications and subagent results
are not the user's messages. Assume the user remembers that message and nothing after it, so
name each pull request, branch or agent as the user would know it, not by an internal id.

**Gather, read-only.** Read the session's own work since the anchor, subagent reports, and
messages from others in the chat. Re-check the current state of each pull request, CI run and
agent the chat touched, rather than repeating what the chat last said; say which are still
running and which could not be checked. This is a status read only; recovering or resuming
an agent stays `/session-flow:keep-going`. Change nothing to gather.

**Action items.** An action item is a decision or step only the user can take: a product
choice, an approval, an irreversible action, or access the session lacks. Include any still
waiting from before the anchor. Work the session can still do itself is not an action item.

**Order of the reply.**

1. **Needs you**, first. It opens with the number of action items, or says there are none
   and stops when nothing happened since the anchor.
2. **What happened**, most important first, each result with what it means for the user. Skip
   steps that changed nothing. Give one line for work left that the session can do itself.
3. **Each action item**: the decision, why it matters now, the options and what each costs,
   the recommendation, what happens if the user does not answer, and any part not known, said
   as unknown.

Add a visual (table, diagram) only when one exists or can be built from what is in hand; never
invent a number or picture.

## Boundaries. Pick the right sibling

- **`/session-flow:workflow`**. "What stage is next." Orientation reports
  where we stand; it does not prescribe the next step.
- **`/session-flow:reanchor`**. "Are my assumptions still true against
  live reality." Orientation synthesizes current state; it does not run a
  freshness/drift verification. When freshness is in doubt, it points here.
- **`/session-flow:keep-going`**. Recovers and continues off-thread work.
  Orientation reports off-thread work at a glance; it recovers nothing.
- **`/session-flow:retro`**. "What did we learn" (end-of-session scoring +
  codify). Orientation extracts no learnings and scores nothing.
- **`/session-flow:handoff`**. Writes a save-point and ends the session.
  Orientation writes nothing and ends nothing.

## Boundary, the built-in `/recap` command

Both answer "where were we", so a request to catch up can land on either.

- **`/recap` (built-in command)**: generates a one-line summary of the current conversation on
  demand, alongside the automatic recap shown when you return to an idle terminal. It writes nothing
  to disk and reads nothing outside the conversation. It is reserved for the person to run; the
  model does not invoke it.
- **This skill (marketplace plugin).** A four-part briefing that adds what the conversation
  does not hold: handoff save-points, workflow checklists, running-retro ledgers, open PRs and
  work items, git state, and off-thread work at a glance.

**Routing.** When the person wants only a one-line reminder of this conversation, offer it to
the person: you can run `/recap` instead of or alongside this skill. Make the offer at the end
of the briefing, or at the start when the ask names only the current conversation. Prefer this
skill whenever durable or off-thread state matters. An unattended run records the offer in its
output instead of asking.

**Mutation gate.** Neither writes files. This skill never runs `/recap` on the person's behalf.

**Availability is never assumed.** The command can decline in some hosts, for example when the
request is relayed from a chat thread, a routine, or a webhook; this section states what to do
when the person can run it, never that it is present. The four-part records live in
[reference/native-recap.md](reference/native-recap.md).

## What this skill does NOT do

- **Writes nothing**, no files, no memory, no `/clear`. It is a read-only
  briefing that leaves state untouched.
- **Does not verify freshness**. It reports what the durable state says;
  confirming those claims still hold is `/session-flow:reanchor`.
- **Does not recover off-thread work**. It names what is in flight;
  inspecting and resuming it is `/session-flow:keep-going`.
- **Does not prescribe the next stage**; that is `/session-flow:workflow`.
- **Does not score or codify**; that is `/session-flow:retro`.
- **Does not invoke the built-in `/recap`**. Built-ins are not
  Skill-invocable; it synthesizes the conversation summary inline instead.

## Gotchas

- The durable state can be stale; a handoff or ledger describes the moment
  it was written, not now. Report it as "the handoff claims X," and route a
  freshness check to `/session-flow:reanchor` rather than asserting it as
  current fact.
- Optional tools (`gh`, a tracker CLI) may be absent or unauthenticated.
  Degrade to the state you can read and say what you could not reach; never
  block the briefing on a missing optional source.
- Off-thread work is reported at a glance only. The moment the ask becomes
  "resume it" or "is it stuck," that is `/session-flow:keep-going`, not this
  skill.
