---
description: "Accept the recommendations in the agent's latest message after a full evidence check: each is re-grounded in the affected code and current sources, changed or unconfirmable ones come back as old, new and why, and plain-word exceptions override single items. Use when: 'go with recommendations', 'go with your recommendations', 'approve', 'accept all', 'do what you recommended'."
argument-hint: "[exception ...]"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Accept the latest recommendations after a full evidence check
---

**Arguments.** `[exception ...]`, each in plain words. e.g., /go-with-recommendations,
/go-with-recommendations except Q3: use the queue, /go-with-recommendations skip the rename

Accepting is the person's decision; this skill makes sure what they accept still stands on current
evidence before any of it runs.

## 1. Collect the recommendations

Take every recommendation in your latest message to the person: each option you recommended, each
verdict, default and next step put to them for a decision. Number them as that message did (`Q3`)
or, where it numbered nothing, in order (`1`, `2`). With none, say there is nothing to accept and
stop.

Apply the arguments: an exception that names an item replaces or drops that item in the person's
own words; one that names no item ("skip the rename") applies to the item it describes. An exception
that matches no item, or matches two, is asked about before anything runs; the items it does not
touch go ahead.

## 2. Check for an absence

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" status --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}"` and read
`status`, `report_by` and `report_path` from its JSON. A failed run means no absence. When `status`
is `active`:

- The report's Needs you items are recommendations too: add each one's `Recommendation:` to the
  list, numbered by the report.
- A refused action (an `R<n>` id in the report's refused block) is never accepted here, whatever
  the exception says: it waits in the report for the person's return.
- The absence itself stays as it is until step 4.

## 3. Run the evidence check

Invoke `/discipline:do-your-research full` (if enabled) via the Skill tool.

It audits the collected recommendations as pending ones. When the Skill tool reports that skill
missing or the discipline plugin off, carry the same audit inline, for each recommendation:

- Ground it locally: read the code, config or document it changes and list who consumes it,
  other repositories included.
- Ground it externally: fetch the current official source for every tool, version, API or pattern
  it rests on, with a release or changelog check for anything that ships releases, and a second
  source from a different origin before it carries a decision. Recall is not a source.
- Give it exactly one outcome: `Basis: verified` with the `file:line`, tool output or URL read this
  session; `Basis: judgment` only when it is not consequential (cross-repo, shared, hard to reverse,
  costly or security); or withheld as an open question naming the evidence that would settle it.

## 4. Report, then act

Before acting, show each item once: unchanged with why, or `old → new → why` when the evidence
moved it, each with its `Basis:` line. A withheld item is flagged and does not run; it is
restated in full at the end of the reply as an open question with its options and recommendation.

Then, during an absence, decide whether it ends: it stays active only while `report_by` is set and
has not passed, where an early accept from afar is plausible. Otherwise follow the step-away rules'
"Coming back": this command is the person's own, so end the absence with
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" end --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}"`,
and show the report once and deliver it.

Then carry out every accepted item: unchanged ones, moved ones in their new form, and exceptions in
the person's words. While the absence stays active, mark each accepted Needs you item `Accepted:` in
the report; the Stop hook keeps the report's script-owned blocks current.

## What a bare accept never approves

An accept with no exception naming the item never approves:

- an action the permission system or an away hook refused;
- a permission or trust-boundary change, such as a new allow rule, a loosened security control or
  a change to who or what can act;
- an action that could cost money, judged against the person's own cost rules where they have
  written them, such as one the away report parked for that reason.

List each such item as still waiting on the person, with what it unblocks; an exception that names
it is the go-ahead, except for a refused action during an absence.

## Next

/session-flow:workflow

Names the next stage once the accepted work is under way.

## Gotchas

- The evidence check can move a recommendation the person just accepted. Accepting the old form
  because they said yes skips the check they asked for; run the new form and show the move.
- "Approve" typed during an absence is not a return. Before report-by, the absence stays active;
  the step-away rules decide when the person is back.
