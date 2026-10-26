---
bump: patch
---

### Fixed

- `apply-patch.mjs` drops a pull request push, as held, when the pull request body carries a body hold (a line opening with `Hold:` in any case after any whitespace, NBSP included, with a bare CR also ending a line, or "do not merge"), read with merge-holds.mjs's `BODY_HOLD`, unless the lanes App opened the pull request: there the line holds the merge, not a fix. It covers every pull request push, merge rows included. The lanes App's login is now one export of merge-holds.mjs, which `clear-escalations.mjs` and `refire-refused.mjs` read too, and the write runner copies merge-holds.mjs beside apply-patch's base copy.
