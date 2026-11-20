---
bump: minor
---

### Added

- **Inherited security and design decisions carry their rationale.** A `Decisions in force` entry tagged `[security]` or `[design]` after its id ends with `buys:`, `surface:` and `cost:`. `save_point.py validate` fails a tagged entry missing any of the three and names the fix (`add buys:/surface:/cost: to D<n>`); untagged entries, and older handoffs, still pass. `/session-flow:reanchor` prints each tagged decision's three fields on resume and sends a decision back to the owner before work builds on it when its cost exceeds what it buys, or a security decision exposes no surface.
