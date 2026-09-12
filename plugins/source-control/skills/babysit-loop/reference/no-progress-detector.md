# No-progress detector (merge lane)

This lane's binding of the loop-lane convention's consecutive-no-progress detector. Counter
semantics are the convention's
([`docs/conventions/loop-lane/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/loop-lane/README.md)
§4, "No-progress detector"), held by citation and never restated here: the increment/hold/reset
states, the escalate-and-keep-looping rule, the author-matched single open escalation, the
no-self-reset rule, and the resumption comment. `SKILL.md`'s cycle-shape step 6 owns when the counter is updated; this file owns
what the merge lane counts.

## Qualifying progress

Since the previous cycle, a watched PR merged or closed, or materially changed, or this lane wrote a
new escalation. A material change is a head move, review or comment activity, a checks transition,
or a draft elevated, foreign activity included, since that is the queue moving.

A lane-authored fix qualifies only on the cycle it first lands: re-attempting the same
still-unresolved blocker later is not progress, per the convention's no-self-reset rule. Compare
against the previous cycle's snapshot; across a session restart, anchor on the telemetry comment's
last upsert time.

## Actionable work in view

The cycle-start snapshot holds at least one open PR; otherwise the cycle is idle and the counter
holds.

**This lane's held-cycle bar is `rate_limit_latch`, not the pause window.** The inlined rate-limit
guard floor starts no new mutating work while the latch is set, and the latch outlives the pause
until a fresh healthy snapshot clears it. So a latched cycle is **held** however many PRs the
snapshot carries, and stays held after the pause has lifted. A lane obeying the guard is never
escalated for obeying it, and a latch no healthy snapshot ever clears cannot trip the threshold by
itself.

## Threshold

`babysit_loop_no_progress_threshold` in the layered config (key table in `SKILL.md`'s config
reference; default 3).

## Stall escalation

`SKILL.md`'s Escalation contract, unchanged: a `Lane stall: babysit-loop` issue (exact title)
carrying the human-gated role label and a machine-marked comment whose first line is
`<!-- work-items:escalation lane=babysit-loop kind=escalated -->`, reporting the streak length, the
cycles covered, and what sat unmoved. Deduped on that exact title plus this lane's own write
identity as author, so a third party's lookalike never suppresses the signal.

A stall issue is ordinary human-gated backlog to the drain evaluation, never lane infrastructure.
