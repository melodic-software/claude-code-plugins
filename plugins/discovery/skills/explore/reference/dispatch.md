# Dispatch contract — the parent's side

`SKILL.md` carries the routing mandate and the acceptance gate's three steps. This file carries why
each step is shaped the way it is, and what the parent does when one fails. The agent's own side is
`plugins/discovery/agents/explorer.md`.

## Why the gate reads the slice path, not the payload

The failure this gate was built from is a real one: a dispatched `explorer` returned
`status: complete` carrying a mid-stream narration line as its whole payload — no `preload_token`,
no summary, no artifact path — and the parent proceeded as though exploration had finished.

A check that resolves its input from `artifact:` cannot see that failure, because the payload it
would read the path from is the thing that is broken. The parent already holds the answer: it
resolved the memory-slice path itself, before dispatch, and put it in the dispatch prompt. Grading
against **its own** path is what makes the check independent of every return-path defect, present or
future.

This is only true if the parent still **has** that path when the gate runs. It resolved one before
dispatch, wrote a prompt, waited, and now has a payload sitting in front of it with an `artifact:`
field right there — the wrong input is the convenient one at exactly the moment the gate fires. So
the slice path is carried across the dispatch deliberately, as the gate's input, rather than
recovered from whatever is nearest.

The same reasoning demotes `--expect-sidecars` to a secondary cross-check. It compares the payload's
self-reported count against what the index names, which is worth having — an index and a payload
that disagree mean one of them is wrong — but it is a claim grading a claim. The exit status without
that flag is the load-bearing verdict, which is why the bare invocation is the gate and the flag is
an addition to it. Drop the flag outright on a payload that reported no `sidecars:` count: passing
`0` for a field the run never wrote asks the gate a false question, and it will answer it
truthfully.

## Why existence is not the same as freshness

An artifact being *there* does not mean this dispatch put it there. A slice that already holds a
complete set from an earlier exploration satisfies every on-disk check even when the run just
failed without writing a byte — and the sidecar count agrees too, because both runs write the same
sections. The gate would report success and planning would proceed against a stale snapshot of the
codebase, which is the original failure wearing a different hat.

So the parent creates the slice if it is not there and touches `<slice>/.explore-dispatch`
immediately before dispatching, then passes that file as `--newer-than`. The `mkdir -p` half is
load-bearing on a first-time scope: a bare `touch` into a directory that does not exist yet fails,
and the dispatch either never starts or reaches the gate with no baseline. The index has to be
strictly newer than that baseline. A baseline the parent named but that is not on disk exits 2
rather than quietly reporting `freshness=unchecked`: a check the caller asked for and only appeared
to get is worse than one it knowingly skipped, which is why every opt-in check reports `unchecked`
in the verdict line instead of being absent from it.

## Why the payload's pointer is checked against the graded index

The gate finds the index from the parent's own slice path, so the payload's `artifact:` value plays
no part in selecting what gets graded. That leaves them free to disagree — and a payload naming some
other file is not corroborating the artifact that passed. Worse, its `verification_request.target`
carries the same wrong path, so the sibling verifier would grade a file the gate never looked at,
and the handoff would point a fresh session at it too.

`--expect-index` therefore compares the two, resolving both to a canonical directory plus basename
so that two spellings of one file are one file. On `pointer=mismatch` the **gate's** `index=` path is
authoritative for the verifier and the handoff, and the disagreement itself is treated as a payload
defect, not reconciled silently.

## Why "non-empty" was not enough on its own

The obvious version of this check is `test -s EXPLORE.md`. A mid-stream stub passes it. So does an
index whose sidecars the run died before writing — the truncation shape, where the index names files
that are not there.

The gate therefore requires substance a stub cannot fake: the index names at least one
`EXPLORE-<section>.md` sidecar, and every sidecar it names exists beside it and is non-empty. It
keys on the sidecar **filename** contract rather than parsing the index's section → file table, so a
formatting edit to that table does not break the gate.

It searches the slice root and exactly one level below it, which is the whole sub-slice rule. Two
candidate indexes exit 2 rather than picking one: accepting a prior run's artifact as evidence that
*this* run succeeded is the same class of silent success the gate exists to refuse.

## Recovery ladder

Take these in order. A non-zero exit is never a reason to proceed and note it later.

**Exit 2 — ungradeable.** This is a parent-envelope problem, not a worker problem: the slice path
was wrong, or two runs are sharing one slice. Fix the envelope — the parent assigns sub-slices, so
it can disambiguate — and re-run the gate. Re-dispatching first pays for a whole exploration again
to answer a question the parent could have answered itself.

**Exit 1 with the agent still live — resume it; do not re-dispatch it.** A resume costs one message;
a re-dispatch pays the full six dimensions over again. Address the agent by the **agent ID**, not by
name, and ask for the return payload block alone rather than restating the task. If the artifact set
is on disk and only the payload was malformed, the artifact is the source of truth — read the index
for the pointer, and still dispatch the sibling verifier.

**A refused resume, or exit 1 again after one.** Discard the slice and re-dispatch with the same
envelope. Do not resume a partial slice: a half-written artifact set cannot be told apart from a
complete one by reading it, which is why the truncation rule discards rather than resumes.

**Bound the wait either way.** The consuming session whose report produced this gate spent roughly
eight minutes discovering the resume path by trial. That cost is why the ladder is written down.
`status: truncated` is not a special case — it takes the same ladder.

### What the harness actually guarantees about a resume

Verified 2026-08-08 against <https://code.claude.com/docs/en/sub-agents> (the page
`docs/OFFICIAL-DOCS.md` indexes for subagents), quoting it:

- The parent has the identifier it needs: "When a subagent completes, Claude receives its agent ID."
- The mechanism: "Claude uses the `SendMessage` tool with the agent's ID or name as the `to` field
  to resume it" — and it "doesn't require agent teams to be enabled".
- Why resuming is cheaper than re-dispatching: "Resumed subagents retain their full conversation
  history, including all previous tool calls, results, and reasoning. The subagent picks up exactly
  where it stopped rather than starting fresh." A finished agent needs no new spawn — "A completed
  subagent that receives a `SendMessage` auto-resumes in the background without a new `Agent`
  invocation."
- Why the ID and not the name: "As of v2.1.199, `SendMessage` checks that a name still refers to the
  same agent it reached earlier in the conversation" and refuses the send when a newer agent has
  taken the name. The ID is unambiguous.
- The one case that is not retryable: "As of v2.1.191, a subagent you stopped yourself, with `x` in
  `/tasks` or an SDK `stop_task` request, doesn't auto-resume. The `SendMessage` call returns a
  refusal telling Claude the agent was cancelled." Re-dispatch instead.
- This ladder covers `discovery:explorer` because it is a **custom** subagent. It does not extend to
  the built-in Explore agent that `SKILL.md` names as the one alternative: "The built-in Explore and
  Plan agents are one-shot and return no agent ID, so they can't be resumed."

The page documents no partial-return semantics for `maxTurns`, defining it only as "Maximum number
of agentic turns before the subagent stops" — which is why the agent writes `status: truncated` with
a partial payload *before* its budget runs out rather than relying on the harness to say anything on
its way down.
