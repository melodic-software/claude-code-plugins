# Preflight: proving the fan-out inherits

**Every documented harness claim in this file was verified 2026-11-04, with Claude Code 2.1.318 the
latest release**, reading <https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation>
and <https://code.claude.com/docs/en/env-vars#variables> as fetched that day. Recheck trigger: the
sub-agents page changes what a non-fork subagent or a fork starts with in context, either page
changes what turns fork mode off, or a release note names
fork mode, subagent tool filtering, or `CLAUDE_CODE_FORK_SUBAGENT`. The same stamp covers the fork
claims in [`batched-pass.md`](batched-pass.md), which cites it rather than repeating it;
[`../SKILL.md`](../SKILL.md) carries its own pointer records.

What [`../SKILL.md`](../SKILL.md) runs before step 1 of a full-batch pass, to establish rather than
assume that its subagents inherit this conversation. A batched pass whose members inherited nothing
has nothing to audit, and some share of them will invent a ledger instead of saying so. Session-start
digest mode never runs any of it.

The batched pass's step 3 merges the members' ledgers and its step 4 **writes
their remedies to the working tree**. That is the failure this preflight exists
to prevent: a correctness pass whose failure mode is confident, invented
corrections applied to real files.

**Stage 1. Read your own tool schemas. Zero dispatch, diagnostic only.** Read
one thing: whether the `Agent` tool offers the `fork` type in this session.
Offered means stage 2 can try; not offered predicts a failed canary and points
the report at what turns forks off. We do not read `run_in_background` on
`Agent` or `Bash` as a fork-mode signal: the docs relate fork mode to what a
call that leaves that parameter out does, which only a dispatched call shows,
and this stage dispatches nothing. **This stage never gates**: no page says how
fork mode shows in a tool schema, so neither reading is conclusive. It explains
what stage 2 finds; it never replaces stage 2 and never aborts on its own.

- **Pointer**: when explaining a missing `fork` type, fetch
  [Turn fork mode off](https://code.claude.com/docs/en/sub-agents#turn-fork-mode-on-or-off)
  and [Agent tool behavior](https://code.claude.com/docs/en/tools-reference#agent-tool-behavior)
  live; for how fork mode relates to an omitted `run_in_background`, fetch
  [the SDK's Agent tool reference](https://code.claude.com/docs/en/agent-sdk/python#agent) live.

**Stage 1b. Explicit fork-off short-circuit (zero dispatch).** We read
`CLAUDE_CODE_FORK_SUBAGENT` explicitly `0` as fork mode off. Do not dispatch the
canary or any member. Take the degrade path immediately (below). Every other
state, unset included, proves nothing: a default is not a runtime guarantee, so
in every case but the explicit `0` above stage 2 remains the authoritative test.

- **Pointer**: when stating which sessions and versions have fork mode on by
  default, fetch
  [Turn fork mode off](https://code.claude.com/docs/en/sub-agents#turn-fork-mode-on-or-off)
  and the [`CLAUDE_CODE_FORK_SUBAGENT` row](https://code.claude.com/docs/en/env-vars#variables)
  live.

**Stage 2, an inheritance-proof canary. The decider, and it costs one fork.**
Dispatch ONE fork alone, ahead of the first wave, that answers the proof
question and **nothing else**. No corrector, no audit, no ledger. Gate the
whole fan-out on it. Skip this stage only when stage 1b already short-circuited
on `CLAUDE_CODE_FORK_SUBAGENT=0`; every other state runs it.

It is deliberately not folded into a member's real audit, which would look free
and is not: a fork inherits everything the session holds when it spawns, so a
member ledger returned before wave 1 would sit in every later fork's inherited
context and anchor its audit. Breaking the independence step 3 relies on (see
"the forks stay independent by design"). A proof-only canary returns nothing
that can anchor anyone. Budget the guard as one extra fork; that is what it
costs to know the other ledgers are real.

Every fork, canary and members alike, answers one inheritance-proof question
FIRST, before any audit content, and stops and says so plainly if it cannot.
Conversations differ, so specify the question's *properties*, not a fixed
question. All four are required:

- **Its answer exists only in this conversation's history**, not in a file, not
  in a `CLAUDE.md`, since a non-fork subagent can answer from what it loads at
  startup (read <https://code.claude.com/docs/en/sub-agents#what-loads-at-startup>
  live). Nor derivable from this plugin.
- **The dispatch prompt neither contains nor paraphrases the answer**. Else a
  non-inheriting subagent answers it from the prompt alone.
- **It keys on ordinary inherited material**, a prior user turn or tool result.
  Out-of-band or host-injected content is not documented as inherited and can
  be absent from a fork's transcript, so a proof keyed on it can read as a
  false negative.
- **It cannot be guessed.** An answer a non-inheriting subagent could hit by
  chance, a yes/no, a binary choice, a detail common to most sessions, clears
  the main thread's check without proving anything, and the blind ledgers behind
  it then reach the corrective write, and blind forks guess alike, since they
  share the question and the model, so one lucky answer is not one bad ledger.
  Small-domain values fail this test even when they are exact: a turn count, a
  file count, a finding count are all guessable. Require a long verbatim
  string or a specific identifier, and when in doubt mint the value (below)
  rather than picking one out of the history.

When the conversation offers no detail meeting all four, a thin session that
opened straight into a full batch over an already-dirty tree. Do not degrade.
**Mint one.** A fork carries what the transcript holds when it spawns (read
<https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>
live), so emit a fresh
high-entropy value into the transcript as an ordinary main-thread tool result
BEFORE the canary spawns, and ask for it back. It is unguessable by
construction, exists in no file, and a non-inheriting subagent cannot produce
it, so the proof works at any conversation length, and thin history never
costs the user the audit they asked for.

**Verify on the main thread, and fail closed.** Check the answer against what
this context knows. Absent, ambiguous, or unverifiable proof counts as NOT
inherited, a plausible-looking answer is not a pass, because fabrication is the
exposure being defended against. Canary verified → fan the members out. Canary
unproven → degrade path (exact token, posture digest only); never re-dispatch
the batch blind.

A member that returns unproven LATER, mid-fan-out, is a different case: the
canary already established that inheritance works here, and earlier waves'
ledgers are checkpointed and real. Discard that member's ledger, retry it once,
and if it is still unproven **keep every verified ledger, correct forward from
those, and report the unproven members as open**. Do not throw away proven
audits by collapsing the whole pass to the digest. Reserve the digest for a
failed canary, when nothing has been proven at all.

**Degrade path. Fail closed, loud, posture digest only.** Any preflight
failure. Stage 1b short-circuit on `CLAUDE_CODE_FORK_SUBAGENT=0`, an
unproven canary, a fork dispatch error (`Agent type 'fork' not found` or
equivalent), or any other signal that conversation-inheriting forks cannot run
here. Takes this path. Never re-dispatch the batch blind and never substitute
a sequential inline audit+correct pass on the main thread: that recreates the
salience dilution the declared delta exists to prevent, yields audits
weaker than the ones declined to run, and is indistinguishable from silence in
an unattended context.

The report's **first line** is the exact token. No prefix, no markdown
wrapper, no variant spelling:

```text
SWEEP-ALL: DEGRADED (fork-unavailable)
```

Then state plainly that **no audits ran and no corrections were applied**: zero member dispatches, zero ledger collection, zero corrective writes to the
working tree. Then run the session-start posture digest (mode 1): derive
posture from the listing and tier metadata only, no corrector bodies load, no
audit runs.

**Next actions**, after the digest, name what the user can do instead:

- Invoke any single corrector directly for its full audit+correct loop in this
  context (the shared method's normal per-corrector path, one discipline at a
  time).
- Re-run this skill once fork dispatch can succeed here: clear what turned forks
  off (stage 1b's pointer names the switches), or use a harness build where fork
  dispatch succeeds.
- At conversation start with nothing to audit yet, mode 1 alone is sufficient; no full batch was needed.

That is the same position `setup` reports as the full-batch prerequisite; this
runbook is where it executes.

**What is not documented.** What the harness does when the `fork` type is
requested while fork mode is OFF is **not documented on any current page**.
Subagents may come back with no inherited conversation, but
that is an observation, not a contract; the preflight does not rest on it,
proving inheritance positively rather than predicting the shape of its absence.
