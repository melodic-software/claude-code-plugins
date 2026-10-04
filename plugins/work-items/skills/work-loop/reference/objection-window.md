# Objection window at admission

A rung of the admission gate in [`../SKILL.md`](../SKILL.md), run after the in-flight precondition
and before classification. It applies only to a candidate carrying an objection window comment.

Triage posts an "Objection window until <UTC>" comment when a consumer turned the window on
(`/work-items:triage`'s `triage_objection_window_hours`, resolved there with its layer reported).
Its first line is `<!-- work-items:objection-window until=<end> -->`
([`../../triage/context/apply-outcome.md`](../../triage/context/apply-outcome.md), "Objection
window comment"). A comment is a window comment only when that marker is its first line; the same
text anywhere else in a comment is ignored. Read the newest window comment from the seam's
configured write identity; one from any other author is ignored, so the candidate has no window. The gate reads the end time from the
marker, so a setting changed later does not move a window already posted. The lane never waits on
a window. Check in this order:

1. **Human objection**, open window or not: a comment posted after the marker by a person, and not
   already answered by a later `lane=work-loop` escalation marker on the item. A person here is an
   author that is not the seam's write identity, is not a bot account (the tracker reports its
   user type as `Bot`, or its login ends in `[bot]`), and whose comment carries no AI disclaimer. Step 5 escalates the item as
   `kind=escalated`, whose one-line question names the objecting comment, and it leaves the
   autonomous frontier. The cycle report lists it as `objection: #<item> -> escalated`.
2. **Window still open** (`<end>` after the cycle-start time): skip the candidate this cycle. It is
   not dispatched, classified, or escalated, and none of its labels change. It is not actionable,
   so it neither counts toward nor resets the no-progress streak. The cycle report lists it as
   `objection window open: #<item> until <end>`.
3. **Window over**, or no marker: continue to classification.
