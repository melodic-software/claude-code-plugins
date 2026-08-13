# Drain mode (`--drain`)

The lane stops when the cycle-start snapshot shows every retained id closed or covered by an open,
non-draft close-linked PR, or when the drain-terminal state applies. Lane-infrastructure items never
gate the drain (telemetry issues, open `work-map` containers) — the exclusion contract is owned by
`SKILL.md` "Exit condition" and cited from the loop-lane convention; this file does not restate it.

## Exit condition

Evaluate at cycle end against the cycle-start snapshot's **retained ids, never a fresh seam read**:
every id the snapshot captured — its open items and its autonomous-frontier candidates alike — is
closed or has an **open, non-draft** PR the bound adapter's "Open linked PRs" operation reports as
close-linked (the provider's own computed close-linkage, whose query mechanics and draft exclusion
the adapter owns).

There is deliberately **no second frontier-emptiness limb**. Re-running `list-frontier --autonomous`
here would see items that joined the frontier *after* the snapshot — precisely the mid-cycle intake
step 1 reports and never chases — so a bot filing agent-ready items could hold the drain open
forever. Absence from a later frontier read is also not resolution: an item another session claims,
or one that becomes blocked, leaves the frontier unresolved. Nothing is lost by dropping the limb:
the frontier is derived by filtering `state == open`, so a snapshot frontier candidate is a
snapshot open item either way, and the single test above already covers it — including an item the
snapshot held as untriaged intake that step 2 promoted mid-cycle. That item still holds the drain
open, and it is worked once the admission gate passes it and a cap slot is free.

Satisfied → the drain is complete: set `first_drain_complete`, write the final report (items
closed, PR'd, escalated), apply the post-snapshot intake report below, and stop cleanly.

## Drain-terminal state

When every remaining open item in the snapshot is human-gated or escalated and no PR is in flight,
report and stop cleanly rather than idling forever. Apply the post-snapshot intake report below
before stopping.

## Post-snapshot intake report (every drain exit)

On **every** drain stop — ordinary drain completion and drain-terminal alike — the final report
**names the intake that arrived after the snapshot and was left unworked** — that report is what
keeps "reported, never chased" true once there is no next cycle to sweep it. Compute that list once,
after the exit verdict is already decided, by repeating step 1's **open-items** reading —
lane-infrastructure exclusion and all, per `SKILL.md` — and diffing it against the retained ids. Not
a `list-frontier --autonomous` reading: step 2's sweep hardening routes bot-authored advisory intake
to the human-gated role, which is precisely what that filter excludes, so the frontier reading would
report nothing in the case this sentence exists for. **The read is reporting-only and can never
change the verdict it follows.**
