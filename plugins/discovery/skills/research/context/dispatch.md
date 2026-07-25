# Dispatch contract — the parent's side

`SKILL.md` carries the routing mandate. This file carries what the **parent** owes around a
dispatched run, and why each obligation exists. The agent's own side is
`plugins/discovery/agents/researcher.md`.

## The orchestration boundary

Dispatch moves the reading off the orchestrator's context window. It does not move the *judgement*
that surrounds the reading, and the failures worth guarding against are all at that seam.

**The parent owns the pre-dispatch envelope** — everything that must be resolved in main context
before the agent starts, because the agent cannot resolve it once started:

| Field | Why the agent cannot supply it |
|---|---|
| Resolved topic | `$ARGUMENTS` substitutes to the **empty string** on the preload path, and a non-fork subagent sees no conversation to infer from. The preloaded body reaches the agent reading `Research the following topic:` with nothing after the colon — silence, not a visibly unfilled slot |
| Memory-slice path | Resolved against the consuming repo's topic-docs binding, which is a parent-side lookup |
| Budget | How much depth was authorized is the caller's decision, never the worker's |
| Capability flags | Whether nested spawning is available is a session property the parent probed |

The agent **refuses to guess** any of these rather than inventing one, so an unresolved envelope
surfaces as a failed dispatch instead of a confident answer to a question nobody asked. That refusal
is the reason the envelope is safe to make mandatory.

**The parent owns the post-dispatch boundary** — three obligations, none delegable:

1. **Re-surface `open_questions`.** `AskUserQuestion` is filtered out of every non-fork subagent, so
   the agent returns questions as text. If the parent does not surface them, the anti-pattern the
   skill guards against — silent downstream resolution — happens anyway, one level up.
2. **Dispatch the sibling verifier** for the outcome-gate rows the producer may not self-grade.
   Sibling, not child: independence is a property of *context provenance*, not of spawn parentage. A
   verifier that reads the artifact off disk has never seen the producing context, whoever spawned
   it — which is why nested spawning stays an optimization here rather than a correctness
   prerequisite.
3. **Apply project fit.** The consuming project's conventions and stated direction live with the
   parent; a fresh worker has no access to them.

## Preload liveness — why a sentinel at all

A `skills:` entry that is missing or disabled is **skipped silently**: the harness logs a warning to
the debug log and starts the agent regardless. The resulting run has no disciplines, no phase
structure, and no gate — and it still writes an artifact, still returns a payload, and still reports
`coverage: complete`. At every seam this design builds, that failure is indistinguishable from
success.

So the preloaded skill carries a token, the agent echoes it verbatim, and **the parent discards any
run whose `preload_token` is missing or mismatched**. Not downgrade, not warn, not accept-with-a-note:
the artifact of an undisciplined run is worse than no artifact, because it will be read as though the
discipline ran.

The token lives in `SKILL.md` — the file that is preloaded — and nowhere in the agent definition. An
agent that never received the skill has no way to produce it, which is the whole mechanism.

## Truncation

`maxTurns` has no documented partial-return semantics; the docs define it only as the point at which
the subagent stops. Because the ledger and sidecars are written incrementally, a turn-limit stop
would otherwise leave a half-marked ledger, orphan sidecars, and an index naming files that were
never written — with no payload at all, so the parent never learns the run died.

Hence: the agent writes `status: truncated` with a partial payload **before** its budget is
exhausted, and a dispatch that returns no payload is treated as truncated-without-warning. In both
cases **the parent discards the partial slice rather than resuming it**, because a half-run ledger
cannot be distinguished from a complete one by the coverage script alone.

## What dispatch does and does not buy

- **Independence** — yes. The verdict comes from a context that did not produce the work.
- **Decorrelation** — no, and it never claimed to. One fresh context is still one prior; N of them
  agreeing is not N independent checks. Decorrelation comes from a reviewer with different priors —
  a cross-vendor model — and is orthogonal to dispatch.
- **Bounded summarization loss** — for *content*, yes: the full evidence table, fetch log, and gap
  lists are on disk. For *process*, only as far as those artifacts capture it, which is why the fetch
  log and the gap lists are written outputs rather than working notes.
- **Debuggability** — worse, and worth stating plainly. Background is the default execution mode, so
  a failed run's transcript is not in the conversation at all. The artifact and the payload are the
  evidence; that is why `status`, `coverage`, and `preload_token` are mandatory fields rather than
  nice-to-haves.
