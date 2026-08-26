---
description: "Reconstruct WHY something was built the way it was, from evidence outside the code, review discussion, tickets, design docs, incident records, and report what could not be found as a first-class result. Grades every claim on an intent-evidence tier (Direct / Supported / Inferred / Speculative / Unknown) and cites each one. Use when: 'why was this built this way', 'why did we pick X over Y', 'what were they thinking', 'design rationale', 'what problem was this solving', 'why does this still exist', 'archaeology on this decision'. Skip when: you want what the code DOES or where it lives (that is '/discovery:explore', whose git mode owns repo-local history); when the question is whether a convention should STILL hold rather than why it was adopted (that is '/discipline:reason-dont-recite'); or when the answer is a current external fact rather than a past decision (that is '/discovery:research')."
argument-hint: "<target> (e.g., /discovery:trace-intent the retry backoff in api/client.ts, /discovery:trace-intent why we chose the local-markdown adapter)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Reconstruct why a thing was built this way, from evidence outside the code
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

## Purpose

Code records what a system does. It rarely records why anyone chose it. That lives in review
threads, tickets, design documents, and incident timelines. Records that are partial, contradictory,
and sometimes gone. This skill reconstructs intent from those records and is honest about the parts
it could not recover.

Third axis of this plugin. `/discovery:explore` answers **what IS**, `/discovery:research` answers
**what SHOULD BE**, and this answers **what WAS, and why**. The failure it exists to prevent is a
confident story built from thin evidence: a plausible narrative about a decision is worse than an
admission of ignorance, because it is acted upon.

## Routing. Dispatch by default

**From the main conversation, this skill dispatches the `discovery:intent-tracer` subagent.** Intent
archaeology reads a lot of other people's writing: review threads, ticket histories, design
documents. Keeping that out of the orchestrator's context window is the point. The agent
investigates each resolvable category, writes the artifact set, and returns a file pointer plus a
verification request, not the transcript. The parent resolves the **pre-dispatch envelope** first: six fields (target on the `Topic:` line, reason, memory-slice path, memory root, budget, capability
flags), written into the dispatch prompt as the labelled template in the
[parent contract](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), and owns the **post-dispatch
boundary** after: re-surfacing `open_questions`, dispatching the sibling verifier for tier
assignment, and writing that verdict back into the index.

**Run inline instead** for tight turn-by-turn iteration, for cost, or when the invoking context is
already a subagent, and inline runs the identical discipline; the escape hatch relaxes nothing
below. **An un-runnable gate is not one of the three reasons**: probe `--help` on the artifact
checker before dispatching, and a denied or errored probe **halts** rather than routing you inline.
All three reasons in full, and the halt rule: [`context/dispatch.md`](context/dispatch.md).

**Discipline-liveness token.** A dispatched agent receives this body through its `skills:` preload,
and a preload that fails to resolve is skipped **silently**. Logged to the debug log and nowhere
else. The disk fallback Reads this same file, so a matching `preload_token` is file-identity, **not** proof that preload fired. A missing or mismatched token is a **hard failure: the parent discards the run**. Provenance is `preload: fired | fallback`; `fallback` is the accepted recovery.

```text
discovery-trace-intent-preload-7b3e2d
```

**Pre-dispatch:** create the memory slice and touch `<that slice>/.trace-intent-dispatch` as the
acceptance gate's freshness baseline. Without it a slice already holding an earlier run's index
passes every on-disk check even when this dispatch wrote nothing. **Both shell forms of that command
are in the parent contract**. Copy the one matching this session's shell, because the POSIX form's
`touch` is not a command in PowerShell and its directory flag is a parameter error there.

**Post-dispatch, the payload is graded off disk before it is believed**. `status: complete` is the
agent's claim about its own run, and a claim is not evidence. The gate's three steps, the reason this
family ships no coverage ledger, the by-value rung, and the boundary the parent still owns after the
gate passes are in [`context/dispatch.md`](context/dispatch.md). Two things worth knowing before you
get there: **any non-zero exit halts the workflow**, and a gate that could not run is a FAIL rather
than a skip; and a `claims_by_tier` census sitting entirely in `Speculative` and `Unknown` is a
**successful** run over an undocumented decision, never grounds for a re-dispatch.

## Scope

Investigate the following target: $ARGUMENTS

Under dispatch the target arrives in the dispatch prompt instead. Do not rely on seeing an unfilled
slot: a target that did not arrive in this prompt is a missing target, not an empty one, and it is a
parent-envelope failure the agent reports rather than repairs. Contract:
[`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running
inline with no target, infer it from the conversation, the file, symbol, decision, or convention
under discussion.

## The intent-evidence tier

Every claim carries exactly one tier. The tier measures **how far the claim sits from someone
explicitly stating the intent**, not how confident the run feels, and not how authoritative the
source is. Those are different axes, and merging them is the defect this scale exists to avoid.

| Tier | What it means | How to phrase it | Where it goes |
|---|---|---|---|
| **Direct** | Someone wrote down why. A review comment, a ticket, a design doc, a code comment stating a reason | Confident, present tense: "this exists because X" | What we found |
| **Supported** | No single source says it, but several indirect pieces converge on it | Confident but visibly derived: "the evidence points strongly to X" | What we found |
| **Inferred** | A reasonable reading of context, with nothing explicit behind it | Hedged: "appears to", "likely", "suggests", and show the chain | What we can reasonably infer |
| **Speculative** | Plausible, but rival explanations fit the same evidence | Explicitly a guess: "one possibility is X, but no direct evidence" | Competing hypotheses |
| **Unknown** | Looked, did not find | Name what was searched, not just the absence | What we do not know |

`Unknown` is a finding. A question that was investigated and came back empty tells the reader
something real about how the decision was made. Usually that it was never written down.

### Source reliability rides alongside, and never routes

The tier alone cannot distinguish a review comment written by the change's author from a wiki page
four years stale. Both are `Direct`. So every citation also carries a short reliability note: who
wrote it, how close they were to the decision, and how old it is. This is a note, not a second
ladder. Only the tier decides which section a claim lands in.

### Code shape is not intent evidence

"It handles the null case because it checks for null" is mechanics, not motivation. Reading the
implementation tells you what was built, almost never why. Code-shape inference does not get a low
tier. It leaves the scale entirely and is recorded as a gap.

This is a deliberate departure from the upstream skill this one is reauthored from, which permits
labelled code-shape inference at `Inferred`. The reason is operational rather than epistemic: code
is always present and costs nothing to consult, so a weak-but-admissible rung for it gets filled
exactly when the real record is thin, which is exactly when a reader most needs to be told so.

**Version-control behaviour is not code shape.** Change coupling, churn and hotspot data are evidence
the code alone cannot give you, and they are admissible, but they locate rather than explain: they
show that two files always change together, never why anyone decided that. Behavioural signal reaches
`Inferred` at most, never `Supported`, never `Direct`.

## Evidence categories

Three categories are investigated wherever they resolve, and none is assumed present.

| Category | What it holds | What kind of why it uniquely surfaces |
|---|---|---|
| **Source control** | Commit history, review discussion, merge threads, code comments | Implementation-time rationale captured during review, the problem statement, the alternatives argued, the constraint someone encoded in a comment |
| **Long-form documents** | Design docs, RFCs, ADRs, specs, postmortems | Rationale written out before it became code. Explicit "alternatives considered", the decision record, the postmortem action item |
| **Issue tracker** | Tickets, their labels, their parent initiatives | The product or business forcing function, the customer request, the compliance deadline, the incident follow-up |

Each is **presence-gated**. Source control is not guaranteed either: a run may execute where no
repository resolves, which is the normal condition for a dispatched worker rather than an edge case.
An unavailable category is reported as a gap, never skipped in silence.

Repo-local git archaeology is delegated by invoking `/discovery:explore git` via the Skill tool
when that skill is installed, rather than reimplemented here; without it, read the history directly
and say so. Tracker access routes through `/work-items:track`, invoked via the Skill tool, when the
`work-items` plugin is installed, which owns the
provider-neutral seam; without it, use whatever tracker interface the session actually has, and when
none resolves, report the tracker category as unavailable.

Categories beyond these three, team chat, observability, error tracking, product analytics, carry
real intent evidence and are **not shipped as investigators**: nothing in this marketplace reaches
them, so four permanently-empty investigators would report the same gap forever. Extension seam:
[`context/evidence-categories.md`](context/evidence-categories.md).

## Skipping a category

Exactly two reasons permit skipping, and both are written into the output:

1. **The category does not resolve in this environment.** Report it as a gap, not a choice.
2. **The category is provably irrelevant**, not merely unlikely. "This is a build-time script with
   no runtime path, so error tracking cannot hold anything" qualifies.

"Probably not in the tracker" and "docs likely don't cover this" do **not** qualify. Deciding in
advance that a source is empty is how a blind spot becomes a finding. Run the search and let the null
result speak: an empty category costs one search, a missed design document costs a wrong answer.

## Output

Lead with the question restated and the code anchor, then the sections below in order. Sections with
nothing in them are omitted, except **Sources consulted**, which is never omitted.

- **What we found**. `Direct` and `Supported` claims, each cited and each carrying its reliability
  note.
- **What we can reasonably infer**. `Inferred` claims, hedged, each showing its inference chain.
- **Competing hypotheses**. `Speculative` claims, presented together with the evidence for and
  against each. Do not force a winner the record does not support.
- **What we do not know**. `Unknown`. Specific: name the searches that came back empty.
- **Sources consulted**. One line per category, including those that found nothing:

  `- <category>: <what was searched>. <what was found | no relevant results | skipped, reason>.`

When the question precedes an actual change, close with a Preserve / Change / Avoid / Risk
constraint set the planning stage can consume.

**Persist it as `INTENT.md` plus `INTENT-<section>.md` sidecars** in the memory slice, so a fresh
session can resume from the artifact alone. Destination, slug, and runtime guards resolve per the
plugin's topic-docs binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).
The index is the entry point at every size, and **Sources
consulted** lives in it rather than in a sidecar, a reader who takes the answer and stops must still
meet the shape of the record behind it. Header schema, and why neither sibling family's header fits:
[`context/artifact-shape.md`](context/artifact-shape.md).

## Outcome gate

The tier assignments are not this run's to grade. The parent dispatches a fresh context as this
run's reviewer, and this run returns verification pending.

Check these against the written output, not against recollection:

- Every claim in *What we found* cites a specific source, a commit, a review thread, a ticket, a
  document, or a comment with its location.
- No claim rests on the shape of the code.
- Every category appears in *Sources consulted*, including the ones that found nothing.
- Every skip carries one of the two permitted reasons.
- Hedged claims are hedged in the output, not flattened into confident prose.

## Gotchas

See [`context/gotchas.md`](context/gotchas.md).
