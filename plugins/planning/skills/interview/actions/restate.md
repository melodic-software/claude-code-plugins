# Action: restate

Read this when the action is `restate`. It says back, in one paragraph, what the interview has
reached for the topic, and holds there until the user agrees.

## What it reads

Build the paragraph from what already exists for the topic, in this order: the Brief in
`<memory_dir>/<topic-slug>/PLAN.md`, the answered rows of the ledger's open-question register, then
the conversation. Decide nothing new. A part with no settled answer reads `not settled yet`, never a
guess: the user's decisions are never synthesized (SKILL.md "Gates").

## The paragraph

One paragraph of plain prose, three parts in this order:

1. **Goal**, with its "because": what changes, and why the user wants it.
2. **Problem**: what is wrong or missing today, in the user's words where they gave them.
3. **Done**: the Goal's Finish line (when the whole effort is done and who checks it), then how everyone will know it worked, the acceptance criteria condensed to a clause.

No list, no table, and no bare codes: name each item (SKILL.md "Name every code"). Example:

> We are adding a retry budget to the webhook sender, because partners lose events when their
> endpoint blips. Today a failed delivery is dropped after one try and nobody is told. Done means a
> delivery is retried three times, then lands in the dead-letter queue, and the on-call channel gets
> one alert per dead-lettered event.

## The wait (a fixed floor)

In an interactive session, end with an active request, "Reply yes to confirm, or say what to
change.", and wait for the reply. Do nothing else for the topic until it comes. Only an explicit,
unhedged confirmation ("yes", "confirmed") counts: a correction updates the paragraph, which is
shown again in full; a hedged reply ("yes?", "I think so") or a change of subject does not count,
and the request is repeated in one line. No setting, argument or caller turns this wait off in an
interactive session.

This yes confirms the paragraph only. It is never SKILL.md Step 3's confirmation gate, which still
runs before the contract locks. On the page surface, post the paragraph as a `note-reply` with
`needsAnswer` and wait for the reply; never use the `restate` op, which is that gate's and feeds the
Brief export ([`../context/surface.md`](../context/surface.md) "Confirmation gate").

Unattended, which only the caller declares (SKILL.md Step 1.5, "Unattended path"), print the
paragraph under `Restatement: UNCONFIRMED` and do not wait. Silence is never a yes.

## After the yes

The restate writes no register row; it asks nothing the register tracks. Reached mid-interview,
carry on from the round it interrupted. Run on its own, recommend the next step: `me` when a part
read `not settled yet`, otherwise `lock`.
