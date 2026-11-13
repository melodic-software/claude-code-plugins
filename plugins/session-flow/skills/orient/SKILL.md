---
description: "Read-only orientation from durable state (ledgers, handoffs, open PRs and work items, git): where the session stands and why, or a zoom-out timeline of the whole effort. Use when: 'where were we', 'catch me up', 'situation report', 'zoom out', 'when did we start', 'what did we do each day'. Writes nothing. Past attempts: /session-flow:recall."
user-invocable: true
disable-model-invocation: false
argument-hint: "[catch-up|zoom-out [--days <N>]] [--unattended]"
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
   Report the off-thread work at a glance. In the four-part briefing, do
   **not** inspect or recover it; that is `/session-flow:keep-going`.

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
argument `catch-up`; a bare "catch me up" keeps the four-part briefing. `--unattended`, anywhere in the arguments,
is not that argument: it is the caller declaring that nobody is present, so take it out first and
match `catch-up` against the rest. It answers "what
happened since my last message, and what needs me", still read-only.

**Word cap.** The What happened part stays within `${user_config.orient_catch_up_word_cap}`
words, visuals excluded. A value still reading `${user_config.…}`, or empty, is unset: the cap is
250. A value below 150 is treated as 150. The cap never costs an action item: list every one in
full, even past the cap, never as a count, never merged with another, never as a link in its
place. To fit the cap, shorten What happened.

**Anchor.** The user's last message they wrote themselves. Notifications and subagent results
are not the user's messages. Assume the user remembers that message and nothing after it, so
name each pull request, branch or agent as the user would know it, not by an internal id.

**Gather, read-only.** Read the session's own work since the anchor, subagent reports, and
messages from others in the chat. Re-check the current state of each pull request, CI run and
agent the chat touched, rather than repeating what the chat last said; say which are still
running and which could not be checked. This is a status read only; recovering or resuming
an agent stays `/session-flow:keep-going`. Change nothing to gather. This is the one scope of
this skill that re-checks live state; every "does not inspect", "does not verify" and "reports
at a glance" limit below and above applies to every other scope.

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

When `/explainer-video:produce` is among the available skills and the reply did not stop at
Needs you, end the reply with a one-line offer of a video of the catch-up, and on a yes hand the
catch-up to that skill, which owns how the video is made. When that skill is not available, say
nothing about a video. Unattended, record the offer in the output instead of asking.

## Zoom-out scope. `/session-flow:orient zoom-out [--days <N>]`

The whole effort, not just this session: when it started, what each day and each session did and
left, what runs now, and what comes next. It runs on the argument `zoom-out` (strip `--unattended`
first, as for `catch-up`), or when the ask is about the effort's history across sessions: "zoom
out", "when did we start", "what did we do each day". A bare "catch me up" keeps the four-part
briefing. `--days <N>` sets the last-N-days horizon; with none, or a value that is not a positive
whole number, it is 7.

**Effort boundary.** A boundary the ask names (a container, branch, plan file or topic) wins.
Otherwise take the first of these that resolves, and name the one used, with its value, in the
report's first line:

1. **Spec container**: the open container item the current branch's work item links to, read
   through `/work-items:track` when it is among the available skills.
2. **Branch**: the current branch, when it is not the default branch.
3. **Plan file**: the plan file the conversation names.
4. **Topic slug**: the frontmatter `topic` of the handoff this session resumed from.

When none resolves, say so, report only today and the last N days from git, and say the user can
name a boundary in the ask. The effort's handoff chain is the newest handoff in
`<memory_dir>/handoffs/` that matches the boundary (its branch, plan, topic or linked item),
walked back; the directory also holds unrelated tasks' handoffs, so never take the newest file
alone.

**Timeline.** Build one row per session from the chain
([`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`](${CLAUDE_PLUGIN_ROOT}/reference/structure.md)
"Prior sessions" and the frontmatter shapes):

- Read the newest file's `chain:` (or `chain_root` and `hop`) for how many sessions the chain
  holds, its `## Prior sessions` rows (date, session id, transcript, did/left, file), and its own
  `## This session` line as the newest row.
- When the table lacks a row for any earlier session in the chain, walk `previous_handoff` to the
  root, taking each file's frontmatter `date` and `session_id` and its `## This session` line,
  until every session has a row. A file with no `This session` line gives an `UNVERIFIED` row
  from its Resumption brief. A row that differs between a table and the file it names is a
  disagreement, reported as one.
- The effort started at the earliest of the chain root's `date`, the boundary's first commit and
  the container's creation; give each candidate when they differ. Find the first commit with no
  date bound, so it can be older than the other two: for a branch boundary it is the first line of
  `git log <default branch>..HEAD --reverse --format='%h %as %s'`; otherwise it is the first line
  of `git log --reverse <boundary match> --format='%h %as %s'`. The boundary match is
  `--fixed-strings --grep=<term>` for the plan file's name or the topic slug. For the container
  id it is `--extended-regexp --grep='<container id>([^0-9]|$)'`, so the search for `#200` does
  not also match `#2001` or `#20000`.
- Group the rows by day, from the effort's start to today. Fill each day with no handoff row from
  git, one command per call, and merged pull requests. For a branch boundary run
  `git log <default branch>..HEAD --format='%h %as %s'`; otherwise run
  `git log --since=<effort start> <boundary match> --format='%h %as %s'`, with the same boundary
  match as above and the effort start being the earliest date found above, and keep the commits
  that name the boundary. Then run `/session-flow:recall` once, its topic the
  boundary's topic slug or the branch's distinctive words, and place its dated results on those
  days. Show a day only when a source has something for it, except inside the last N days, where
  an empty day is shown as empty. Transcripts reach this scope only through handoff rows and
  recall's report; never open a transcript file here.

**Roadmap.** Near term comes from the plan's open phases, the newest handoff's remaining actions
and recorded preconditions or deviations, and open tracker items linked to the boundary. Long term
comes from later plan phases and the container's open children. Report what each source holds;
never invent a phase.

**Provenance.** Every claim ends with its source label: `[git <sha>]`, `[handoff <file>]`,
`[tracker <id>]`, `[plan <file>]`, `[recall]` or `[conversation]`. When two sources disagree, give
both with their labels, and point to `/session-flow:reanchor` to settle which still holds.

**Order of the reply.**

1. **Boundary**: the rule used and its value, and when the effort started.
2. **Today**, then **Last N days**, then **Earlier** back to the start: the per-day, per-session
   timeline, one row per session with its date, session id, did and left.
3. **Now**: what is in flight (open PRs, off-thread work at a glance, the newest handoff's state).
4. **Near term**, then **Long term**: the roadmap above.
5. **Open decisions**, last: each open question in the newest handoff, the plan or the linked
   tracker items, restated in full with its options, what each costs, and a recommendation. With
   none recorded, say so.

A session timeline (a Gantt chart) or a phase-status diagram is optional: offer it in one line
above the open decisions, and on a yes hand the rows to `/visualization:visualize`, which owns the
form and the medium, including a shareable page. Unattended, record the offer in the output
instead of asking.

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
- **`/session-flow:recall`**. "What did we try for X" across transcripts,
  reverts and closed PRs. The zoom-out scope calls it only for days the
  handoff chain does not cover.

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
the person: If /recap is available in your session (gate basis: ungated, though some hosts decline
it, as **Availability is never assumed** below says; records in
[reference/native-recap.md](reference/native-recap.md)), you can run it instead of or alongside this
skill. Make the offer at the end
of the briefing, or at the start when the ask names only the current conversation. Prefer this
skill whenever durable or off-thread state matters. When the caller passes `--unattended`, the run makes no offer; without that flag
it asks.

**Mutation gate.** Neither writes files. This skill never runs `/recap` on the person's behalf.

**Availability is never assumed.** The command can decline in some hosts, for example when the
request is relayed from a chat thread, a routine, or a webhook; this section states what to do
when the person can run it, never that it is present. The four-part records live in
[reference/native-recap.md](reference/native-recap.md).

## What this skill does NOT do

- **Writes nothing**, no files, no memory, no `/clear`, in every scope,
  `zoom-out` included. It is a read-only briefing that leaves state untouched.
- **Does not verify freshness** (in every scope but `catch-up`, which re-checks
  live status, see its scope). It reports what the durable state says;
  confirming those claims still hold is `/session-flow:reanchor`.
- **Does not recover off-thread work**. It names what is in flight;
  inspecting (beyond the `catch-up` status read) and resuming it is
  `/session-flow:keep-going`.
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
