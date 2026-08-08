# Autonomous-pipeline reminder

A drop-in standing reminder for a pipeline that runs without a human turn between steps. It is
written to be pasted into the system prompt, launch prompt, or dispatch brief of **an adopting
org's own pipeline** — this plugin's lanes are one consumer, not the audience.

## The failure it prevents

Two shapes, and neither announces itself as a failure:

- **A turn that ends on unexecuted intent.** The final message states what will be done — "next
  I'll update the callers", "now running the suite" — and no tool call follows it. In an
  interactive session the human reads the sentence and says "go"; in a pipeline nobody does, so
  the stated work never happens and the run reports as finished.
- **A turn that stops to ask for permission the pipeline already granted.** The model has
  everything it needs to proceed and asks anyway. The cost is not one wasted cycle: the question
  reaches no reader, so the lane sits until a timeout retires it.

Both are *stopping* failures rather than *doing* failures, which is why review catches them late.
The artifact a run leaves behind looks reasonable; only the absent effect gives it away.

## The reminder

Paste this block verbatim. Its clauses are written to be read as a set — the self-check earns its
place only because the enumerated shapes below it say what to check *for*. The pause clause folds
in the companion checkpoint instruction the source guide asks to be paired with this reminder,
rather than leaving a consumer to notice the cross-reference and assemble two blocks.

```text
You are running as an autonomous pipeline. No human is reading your messages between
turns, and no one will answer a question you ask. Work accordingly.

Proceed without asking on anything reversible that follows from the original request.
Committing to a branch, opening a draft, writing a file, running a test, filing a
follow-up — all of these are yours to do. Pause only where the work genuinely requires
the person who launched you: a destructive or irreversible action, an action that
leaves the working environment, a real change of scope, or input only they can supply.

Asking once and proceeding is fine. Asking again about the same thing is not: if the
question was already settled, or the pipeline's standing authorization already covers
it, act rather than re-opening it. Offering follow-ups once the task is done is also
fine — that is a report, not a request.

Before you end a turn, read your own final paragraph back. If it describes an action
rather than reporting one — if it says you will, are about to, are going to, or plans
to — that action has not happened yet. Do it now, in this turn, with tool calls.

These shapes are work orders to act on, never messages to end on:
  - a statement of what you intend to do next
  - a plan, or a list of remaining steps
  - an analysis that stands in place of acting on it
  - a question of the form "want me to", "should I", "shall I", or "do you want"
  - an offer to continue, expand, or clean up afterwards
  - a promise about work you have not done, including "let me know when"
  - a summary that stands in place of the change it describes

End the turn only when the goal is met, or when you are blocked on something only the
person who launched you can supply. If you are blocked, say what you are blocked on and
what you already tried — that message is the whole value of the stop.
```

## Where it applies, and where it does not

**Applies** to any run with no human turn between steps: a scheduled routine, a queue drain, a
`/loop` lane, a dispatched worker, a background agent.

**Does not apply** to an attended lane. A pipeline whose whole design is "recommend, then wait for
my direction" wants the opposite posture, and pasting this block into one converts a working
human-in-the-loop review into an agent that acts on its own recommendations. This plugin's own
worker and merge lanes carry the reminder; its attended queue deliberately does not, and that
two-of-three split is the contract rather than an inconsistency.

## Relationship to the lane-stop gate

`hooks/lane-stop-gate.sh` is the mechanism half, and it covers exactly one clause: the last one.
On a lane's first unsignaled stop it blocks once and re-injects a completion self-check, and a
lane that stops again is treated as genuinely down and reported to the operator.

Two limits are worth stating plainly, because a mechanism that looks like it covers the whole
reminder is worse than one known to cover a slice:

- **The gate performs no content classification** of the final message beyond a literal check for
  its completion sentinel. It cannot tell a turn ending on a genuine blocked-on-user question from
  one ending on a lazy premature stop; both receive the same single nudge. The over-blocking is
  benign — a genuinely blocked lane costs one wasted nudge, then stops with the operator alerted,
  which is what a blocked lane wants — but it is over-blocking, not classification.
- **The remaining clauses have no mechanism** and are carried by this reminder alone. A shell hook
  cannot judge whether a final paragraph describes an action or reports one.

A mechanism outranks an admonition wherever the shape allows one. Here the shape allows one for a
single clause, and the honest arrangement is the gate for that clause plus stated instruction for
the rest — not a gate presented as if it covered all seven.

## Provenance

The clause set is this repository's own wording of guidance published in a model vendor's prompting
guide for its frontier model. It is authored here rather than reproduced, per this repository's rule
against hand-copying upstream content — so it is a locally-owned artifact that cannot silently drift
out of sync with a copy, while the guide stays the thing to read when the upstream advice changes.

**The citation, the exact section, and the recheck trigger live in the plugin
[`README.md`](../README.md), not here.** These `reference/` contracts are written in surface classes
rather than vendor names, so naming the source belongs on the surface that is allowed to name it.
