# Dispatch — the parent's side of a `discovery:intent-tracer` run

Intent-only. Everything identical across this plugin's three dispatched families — the envelope's
field list, both shell forms of the pre-dispatch baseline, the `$ARGUMENTS` claim, the agents' write
boundary, and the resume-before-discard ordering for a partial slice — lives in
[`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md)
and is not restated here. `SKILL.md`'s **Routing** section owns the dispatch-by-default decision and
the discipline-liveness token. This file owns the three inline escape hatches and what the parent
does with the payload once it comes back.

## The three reasons to run inline

Inline runs the identical discipline; the escape hatch relaxes nothing in the gate below. Exactly
three reasons qualify:

- **Tight turn-by-turn iteration** — you will redirect the search as findings land. Dispatch is a
  pre-run choice, and the steering loss is mid-run.
- **Cost** — a dispatched run pays full depth every time, including for a question whose answering
  review thread you can already name.
- **The invoking context is already a subagent.** Dispatch-by-default is scoped to the
  main-conversation boundary, so a subagent invoking this skill runs it inline: the outer dispatch
  already supplied the fresh context. Hoisting, not nesting.

**An un-runnable gate is not a fourth reason.** Before dispatching, probe `--help` on
`check-dispatch-artifact.sh`; the probe is side-effect-free and exits 0. A denied, declined or
errored probe **halts** — taking the inline path to dodge a post-dispatch gate you could not run is
the self-grade this plugin refuses everywhere else. Invocation forms (shebang path, `bash`,
PowerShell lane) and the halt rule are in the parent contract.

## Post-dispatch acceptance gate — before the payload is believed

`status: complete` is the agent's claim about its own run, and a claim is not evidence. Grade the run
**off disk**, against the memory-slice path from the parent's own pre-dispatch envelope — carry that
path across the dispatch, because it is this gate's input — never a path read out of the payload. The
failure this gate exists to catch is a payload carrying no pointer at all.

1. **The payload is well-formed.** `preload_token` matches the token verbatim, `preload:` is `fired`
   or `fallback`, and an `artifact:` pointer is present. Missing token or artifact is a **failed
   dispatch** whatever `status` says; a missing token is a discard rather than a downgrade. A missing
   or unrecognized `preload:` field is an out-of-date agent definition, not a pass. A matching token
   is file-identity only — MUST NOT infer `fired` from it — and `preload: fallback` is not a discard.

   **And `topic_as_received` matches the target the parent actually sent** — compared against the
   envelope the parent wrote, not against what it meant. It is the only check here that fires on an
   input that is present and wrong. A mismatch is a failed dispatch: re-dispatch with the target
   restated in a form that survives the trip; do not accept the artifact and mentally translate it.
   A well-formed payload carrying no `topic_as_received` is an out-of-date agent definition, not a
   pass.

2. **The artifact set is actually on disk, and this run put it there.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" <the retained memory-slice path> \
     --index-name INTENT.md \
     --newer-than <that slice>/.trace-intent-dispatch --expect-index <the payload's artifact: value>
   ```

   Cite the **exit status** — 0 usable, 1 no usable artifact set, 2 ungradeable — not a reading of
   the directory, because the context most motivated to call the dispatch finished is the one that
   would be doing the reading. Only the slice path and `--index-name` are required, and that bare
   form is still a real gate: every optional check reports `unchecked` rather than passing quietly.
   Append `--expect-sidecars <n>` when the payload reported a `sidecars:` count, and **drop any flag
   whose value the payload did not supply**. **The `index=` path in that output is authoritative**
   downstream: the verifier's `target` and the handoff pointer come from it, not from `artifact:`.

3. **The coverage map is read, not scored.** `categories_unavailable` carries a reason per entry, and
   the only two admissible reasons are the two under **Skipping a category** in `SKILL.md`. An entry
   giving any other reason — "probably nothing there", "unlikely to be documented" — is a **failed
   dispatch**, because deciding in advance that a source is empty is the blind spot this skill exists
   to refuse and it is invisible in a finished artifact.

   **There is deliberately no coverage script here and no ledger.** This family's corpus is whatever
   the environment happens to expose, so an enumerate-then-mark ledger would count rows against a
   denominator nobody can fix in advance — the opposite of what research's ledger buys, where the
   corpus is enumerated before the first query. The check that replaces it is the reason-per-skip
   rule above.

## What a thin result is, and is not

`claims_by_tier` sitting entirely in `Speculative` and `Unknown` is a **successful** run over a
decision nobody wrote down, and is never grounds for a re-dispatch. Re-dispatching on a thin census
is how a second run learns to promote claims: the only way to change that shape is to grade the same
evidence more generously, and the tier exists to make exactly that move visible. What a thin census
does warrant is surfacing it — the answer to "why was this built this way" is sometimes "the record
does not say", and that is a finding the requester needs.

A re-dispatch is warranted when the gate above fails, or when a category the agent reported as
unavailable turns out to be reachable after all — a forge or tracker surface the parent can supply
that the run did not have. That is a different envelope, not a retry of the same one.

## Any non-zero exit halts the workflow

A gate that could not run at all is a **FAIL, never a skip**. An invocation that is denied, prompts
and is declined, or errors out halts exactly as a non-zero exit does; do not fall back to reading the
directory. Do not proceed to planning, a decision, or an edit on an intent trace that did not happen
— proceeding is the damage a silently-empty return causes; the missing artifact is only how it
starts.

The resume-before-discard ordering for a truncated run or a silent return is in the parent contract
and applies here unchanged.

## The by-value rung — an exception to the halt, not to the gate

Exit 1 with `persistence: by-value` in the payload means the agent finished and its environment
refused every write. There the parent **writes the slice itself** from the artifact bodies the
payload carries verbatim, into the memory-slice path it resolved before dispatch, and then **re-runs
step 2 above**. The workflow proceeds only when that check comes back 0.

Two conditions bind that write:

- **Filenames are checked before anything reaches disk.** Only `INTENT.md` and
  `INTENT-<section>.md`, as bare filenames — no directory component, no `..`, no leading `/`. This
  matters more for this family than for its siblings: the agent's entire input is text other people
  wrote into review threads and tickets, so a name it emits is a name an untrusted source could have
  steered, and on this path the parent is the one performing the write.
- **The bodies must be the artifact.** A by-value payload carrying a summary of findings rather than
  the full artifact bodies is a **failed dispatch**, not a fallback. Nothing in the payload is
  accepted *in place of* the gate passing; `persistence: by-value` routes the parent, and grades
  nothing.

Why the mode exists and where its boundary sits:
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)
("The contract's by-value boundary is the checkout, not the process").

## The post-dispatch boundary the parent still owns

The gate passing is not the end of the parent's work:

- **Re-surface `open_questions`.** The agent cannot call `AskUserQuestion` — it is filtered out of
  every non-fork subagent — so the payload is the only route those questions have to a human.
- **Dispatch the sibling verifier** against the `index=` path, with the criterion the payload's
  `verification_request` names: each claim's tier is warranted by the sources cited for it, and no
  `Inferred` was promoted. That verifier is a fresh context that has not seen the run, which is the
  whole reason the producer may not grade it.
- **Write the verdict back into the index.** `verification: pending` says the producer may not grade
  its own tiers, not that they are permanently ungraded. An index left at `pending` hands the next
  reader an artifact whose central claim — that these tiers are honest — nobody ever checked.
