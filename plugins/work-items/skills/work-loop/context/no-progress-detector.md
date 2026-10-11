# No-progress detector (worker lane)

The counter semantics: increment on an actionable-but-zero-progress cycle, hold on an idle cycle
and on a guard-held one, reset on any qualifying progress, escalate at the threshold and keep
looping, at most one open stall escalation (author-matched), neither the stall escalation nor a
repeat attempt at the same still-unresolved blocker ever counting as progress, the resumption
comment when progress returns while a stall escalation is open, are the convention's (§4,
"No-progress detector"), held by
citation. This lane's specifics:

- **Qualifying progress** (worker lane, an item advanced or a PR opened): an admitted item
  executed to an opened PR or a closed item, or an item's tracker state advanced by this lane,
  swept to a triage routing outcome, escalated (step 5), or queued for C3 ratification. A stale
  in-flight escalation is not progress. A dirty execution that changed no tracker state (retried next cycle) is not progress; a dirty item that
  escalated off the item is.
- **Actionable work in view**: the cycle-start snapshot holds at least one autonomous-frontier
  candidate or untriaged intake item. A candidate the admission gate's in-flight precondition
  excluded is waiting on its PR, not on this lane, so it does not count, stale or not. Otherwise the cycle is
  idle and the counter holds. A cycle in which the rate-limit guard barred this lane from claiming new work is **held**, and the
  counter likewise holds whatever the snapshot carries. For this lane the bar is the pause window
  itself (the inlined floor above. Drain-then-pause): `rate_limit_latch` gates only adaptive-cap
  ramp-up here, so it alone never holds the counter, per the convention's held-cycle rule.
- **Stall escalation**: the convention's escalation contract, unchanged, create a tracker item
  through the seam `create-item` verb (title `Lane stall: work-loop`, exact match) carrying the
  human-gated role label (resolved from `config.role_labels`, never a literal) and a
  machine-marked comment whose first line is
  `<!-- work-items:escalation lane=work-loop kind=escalated -->`, reporting the streak length,
  the cycles covered, and what sat unmoved in the snapshot. The at-most-one-open check matches on
  the exact title plus the seam's configured write identity as author, exactly like the
  `kind=ratify-c3` dedup. A stall item is ordinary human-gated backlog to the exit evaluation
  (drain-terminal state), never lane infrastructure. A truncated snapshot raises it at once.
