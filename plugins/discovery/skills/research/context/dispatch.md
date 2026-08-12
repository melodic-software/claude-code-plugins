# Dispatch contract — the parent's side

`SKILL.md` carries the routing mandate. This file carries what the **parent** owes around a
dispatched run, and why each obligation exists. The agent's own side is
`${CLAUDE_PLUGIN_ROOT}/agents/researcher.md`.

## The orchestration boundary

Dispatch moves the reading off the orchestrator's context window. It does not move the *judgement*
that surrounds the reading, and the failures worth guarding against are all at that seam.

**The parent owns the pre-dispatch envelope** — everything that must be resolved in main context
before the agent starts, because the agent cannot resolve it once started:

| Field | Why the agent cannot supply it |
|---|---|
| Resolved topic | `$ARGUMENTS` substitutes to the **empty string** on the preload path, and a non-fork subagent sees no conversation to infer from. The preloaded body reaches the agent reading `Research the following topic:` with nothing after the colon — silence, not a visibly unfilled slot |
| Reason the topic is being researched — the decision it feeds and who the output is for | Same blindness as the topic, with a worse failure mode: a missing topic is silence the agent can report, while a missing reason is invisible. The agent researches the topic as written, returns something well-formed, and neither side learns it answered the wrong question. Intent is what decides which of several defensible readings of a topic is the one wanted |
| Memory-slice path | Resolved against the consuming repo's topic-docs binding, which is a parent-side lookup |
| Budget | How much depth was authorized is the caller's decision, never the worker's |
| Capability flags | Whether nested spawning is available is a session property the parent probed |

The agent **refuses to guess** any of these rather than inventing one, so an unresolved envelope
surfaces as a failed dispatch instead of a confident answer to a question nobody asked. That refusal
is the reason the envelope is safe to make mandatory.

**The parent owns the post-dispatch boundary** — the acceptance gate below, and then four obligations,
none delegable (the gate runs first: every one of them acts on an artifact, so all four are worthless
against a run that produced none):

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
4. **Write both results back into the artifact.** This is the obligation easiest to drop, and
   dropping it silently negates the artifact's central promise — that a fresh session can resume
   reading the artifact alone. The producer returns `verification: pending` *because it may not
   self-grade*, not because the question is permanently open; a parent that verifies and then leaves
   the index saying `pending` has produced an artifact that permanently understates what is known,
   and a later reader cannot tell an unverified run from a verified one whose result went unrecorded.

   Concretely, once the sibling verifier returns and project fit is applied, the parent updates the
   index's outcome-gate result: `verification: pending` becomes the verifier's verdict, the verifier
   rows carry pass or the criterion that failed, and project fit is recorded as its own finding
   against the consuming project's conventions. A FAIL on a verifier row sends the run back to the
   phase that row names — the gate's own routing — rather than shipping an artifact annotated with
   its own failure.

   The verifier writes nothing itself. It never saw the run, it holds no envelope, and giving a
   second worker write access to the same slice reintroduces exactly the one-writer-per-slice problem
   the sub-slice rule exists to prevent. It returns a verdict; the parent persists it.

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

## The acceptance gate — why it grades the slice path, not the payload

`SKILL.md` carries the gate's three steps. This is why each is shaped the way it is.

The failure it was built from is a real one, observed on the sibling `/discovery:explore` path: a
dispatched agent returned `status: completed` carrying a mid-stream narration line as its whole
payload — no `preload_token`, no summary, no artifact path — and the parent proceeded as though the
work had finished. Nothing in that shape is explore-specific. A researcher that dies mid-Phase-2
returns the same way, and the sections above already say the parent must discard such a run; what was
missing on this side was any mechanical way to *notice*.

A check that resolves its input from `artifact:` cannot see that failure, because the payload it would
read the path from is the thing that is broken. The parent already holds the answer: it resolved the
memory-slice path itself, before dispatch, and put it in the dispatch prompt. Grading against **its
own** path is what makes the check independent of every return-path defect. That is only true if the
parent still *has* the path when the gate runs — and at exactly that moment a payload with an
`artifact:` field is the nearer input. So the slice path is carried across the dispatch deliberately,
as the gate's input.

The same reasoning demotes `--expect-sidecars` and `--expect-index` to cross-checks: they compare one
of the payload's self-reported values against what the artifact says, which is worth having — a
disagreement means one of them is wrong — but it is a claim grading a claim. The exit status without
them is the load-bearing verdict.

**One gate serves both skills because the on-disk shape is one shape.** `artifact-shape.md` is explicit
that the index shape, the section-keyed sidecar filenames, the sub-slice rule, and both placement rules
are identical for exploration; what differs is the sidecar YAML **header** — tiers and publishing pools
here, `verified: read | grep | inferred` there. The gate never opens a header. `--index-name` is
therefore the whole difference between the two invocations, and it is required rather than defaulted:
a silent `EXPLORE.md` default would grade a research slice against the wrong family and, in a slice
that also holds an exploration, could report a research dispatch that wrote nothing as usable.

**Where the two dispatches genuinely diverge is the fan-out.** `SKILL.md` sanctions a parent that
assigns N sub-slices up front and then *synthesizes* the slice-root `RESEARCH.md` from their indexes.
That end state — a root index plus sub-slice indexes — is the exact shape the gate refuses as
ambiguous, and correctly so: it cannot tell which run wrote which. The obligation is the parent's, not
the script's. Grade each run against the sub-slice it was assigned, and grade before synthesis. An
exit 2 from the slice root after synthesis is the gate working, and it says the parent supplied the
wrong path.

## The coverage ledger is graded separately, and its freshness is not bound

Outcome-gate criterion 11 already makes the *run* cite `check-coverage-complete.sh`'s exit status
rather than its own reading of the table. `coverage: complete` in the payload is that self-grade
travelling one level up, and it inherits the whole problem the criterion exists for: the context
grading the ledger is the context that wants to be finished. Re-running the script parent-side costs
one command and is the only step in this gate that grades the discipline's central bookkeeping rather
than the artifact's existence.

It stays a **separate script**, composed by the skill, rather than a flag on the artifact gate. The
artifact gate is shape-agnostic — it grades an index and its sidecars for either family — and the
ledger belongs to exactly one caller. Folding a `--ledger` flag in would put research's file into the
half of the pair that is deliberately family-neutral.

Two limits are worth stating rather than discovering:

- **`--newer-than` binds the index, not the ledger.** The artifact gate never looks at
  `research-checklist.md`, so a ledger an earlier run left in the slice is not caught by the freshness
  check that catches a stale index.
- **The ledger gate reads marks, not provenance.** It grades the table in front of it and has no
  notion of which run wrote it.

Together those mean a re-dispatch into a dirty slice can be graded against a *dead* run's marks —
narrowly, but really: Phase 0 rewrites the ledger before any query, so the window is a re-dispatch
whose new run recorded the corpus as unbounded (and therefore wrote no ledger) while the previous
run's marked one is still sitting there. Hence the ladder's first move on a discard.

## Recovery ladder

Take these in order. A non-zero exit is never a reason to proceed and note it later.

**Exit 2 — ungradeable.** A parent-envelope problem, not a worker problem: the slice path was wrong,
two runs are sharing one slice, or a fan-out was graded at its root instead of at the assigned
sub-slice. Fix the envelope and re-run the gate. Re-dispatching first pays for a whole research run
again to answer a question the parent could have answered itself.

**Exit 1 with `persistence: by-value` — the parent writes the slice. Take this rung before the resume
rung, because the payload has already told you why the disk is empty.** The agent finished and its
environment refused every write. Neither of the rungs below helps: a resume asks a worker to redo the
one thing it just proved it cannot do, and a re-dispatch pays for every phase again to reproduce the
same refusal — the most expensive way to learn nothing.

So the parent does the writing, which it can — this is the checkout-not-process boundary
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)
already draws, finally reachable from the failure that needs it:

1. **Check every filename before writing anything.** The payload carries `RESEARCH.md`, every
   sidecar with its machine-readable header, and — when the run wrote one — `research-checklist.md`,
   each introduced by a filename. This is the only place in the contract where a name the *worker*
   produced becomes a write the *parent* performs, at the parent's wider permission, and the worker
   that produced it spent its whole run ingesting untrusted third-party pages. Accept exactly
   `RESEARCH.md`, `research-checklist.md`, and `RESEARCH-<section>.md`
   (`^RESEARCH-[A-Za-z0-9_-]+\.md$`), each a bare filename. Reject anything carrying a directory
   separator, a `..` segment, a leading `/`, or any other shape — as a **failed dispatch**, the same
   as a payload returning findings instead of bodies. Confirm the resolved path of every write still
   sits directly inside the destination directory.
2. **Write into the memory-slice path the parent resolved before dispatch** — the same path it fed
   the gate, which on a fan-out is the sub-slice that topic was assigned rather than the slice root.
   The payload's `artifact:` value is the destination the agent *names*, never the anchor.
3. **Re-run the identical checks — the artifact gate always, and the coverage-ledger gate whenever a
   ledger was owed.** Do not hand-inspect the directory instead; the whole reason this rung is safe
   is that the artifact ends up graded by the same checks as every other run. Freshness needs no
   special handling: the parent writes after its own `touch`, so the index is strictly newer than
   the baseline. The slice was empty, so the stale-ledger window this ladder's discard rung exists
   to close does not open here.

   **A run that recorded the corpus as unbounded wrote no ledger, and none is owed on this path
   either.** The standing rule is unchanged — no ledger on disk is correct *only* when the artifact
   records the corpus as unbounded — so check the recovered index for that record, exactly as you
   would for a run that wrote its own slice. Running the ledger gate anyway against a file nobody
   was supposed to write exits 2, which is a FAIL, and would halt a complete run on a check that
   never applied to it. A bounded corpus with no ledger body in the payload is still a Phase 0 that
   never ran, whatever the payload says.
4. Proceed only when every check that applied comes back 0. A non-zero re-run drops through to the
   rungs below — the exception is to the halt, never to the gate, and `persistence: by-value` grades
   nothing on its own.

**A by-value payload that returns findings instead of artifact bodies is a failed dispatch, not a
fallback.** The value of the third outcome is *routing*: it tells the parent which recovery to take.
It is not an acceptance value. Letting the gate grade a claim the agent makes about its own research,
in place of the artifact and the ledger, is the Tier-3 laundering the discipline forbids — arriving
through the recovery path instead of the front door.

**Exit 1 with the agent still live — resume it; do not re-dispatch it.** A resume costs one message; a
re-dispatch pays all the phases over again. Address the agent by its **agent ID**, not by name, and ask
for the return payload block alone rather than restating the task. If the artifact set is on disk and
only the payload was malformed, the artifact is the source of truth — read the index for the pointer,
and still dispatch the sibling verifier. If the payload comes back naming a refused write, you are on
the by-value rung above, not this one. What the harness actually guarantees about a resume, verified
against the official sub-agents page and quoted there, is written down once in
[`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md)
("What the harness actually guarantees about a resume"); it applies unchanged to `discovery:researcher`,
which is a custom subagent like `discovery:explorer`. It is pointed at rather than restated so the two
copies cannot drift apart on a harness change.

**A refused resume, or exit 1 again after one — discard and re-dispatch with the same envelope, and
CLEAR THE SLICE FIRST** (or assign the re-dispatch a fresh sub-slice). This rung is research-specific
and it is the one worth remembering: a discarded run's `research-checklist.md` survives the discard,
the artifact gate's freshness check does not cover it, and a replacement run that finds the corpus
unbounded writes no ledger of its own — so the dead run's marks would be graded as the new run's
coverage. Deleting the slice contents, or moving the re-dispatch to a fresh sub-slice, closes that
without any new machinery.

**Bound the wait either way.** `status: truncated` is not a special case — it takes the same ladder,
and the discard-rather-than-resume rule for a partial *slice* is below, which is a different question
from resuming the *agent* for its payload.

**Why exit 1 alone is not enough to pick a rung.** The gate emits the same exit 1 and the same message
whether the agent never launched or finished every phase and could not write — correctly, since it
grades disk state and nothing else, and reading the payload is not its job. The branch lives here
instead, one level up, where gate step 1 has already put the payload in the parent's hands.

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
