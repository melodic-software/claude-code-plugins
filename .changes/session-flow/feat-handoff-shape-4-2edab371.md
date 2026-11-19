---
bump: minor
---

### Added

- `save_point.py validate` fails a handoff that reuses an id retired anywhere earlier in its
  chain for a different rule, question or decision. Handoffs written from now on carry a
  `checks: 3` stamp, and the check applies only to them; older files validate as before.
- `handoff_chain.py` holds the section table of each handoff shape and one reader of a chain's hot
  files and hop files, which `save_point.py` and `parse_transcript.py --chain-from` now share.
