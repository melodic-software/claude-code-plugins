# work-loop: contributor conventions

## Manual check for the C3 ratification gate

There is no automated test surface for this LLM-executed gate. After editing the admission gate in
`SKILL.md` or `reference/c3-ratification-queue.md`, re-run the gate against an item whose body
carries the ratification phrase and which a "Superseded" comment already restored to the frontier
once after a wrong re-queue. Confirm the item ends the cycle carrying the human-gated role label
with exactly one `kind=ratify-c3` comment, visible as a `[ratify]` row in `/work-items:attend-queue`,
and that no second queue comment was posted.
