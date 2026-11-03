---
bump: minor
---

### Added

- `retro` session mode judges changes earlier retros applied: 2C reads the findings buffer's applied rows and, for each one whose situation this session met, says whether the change was loaded and consulted and gives a verdict (effective, recurring, added work, or not encountered), never proposing removal on missing data. Phase 4 now records each applied finding with `/corrections:codify note --applied` (#12884).

### Changed

- `retro`: a repo with no CI or pre-commit step is still reported, but proposes a check only when a mistake in this session is one that check would have caught; otherwise it is a standing gap with no proposal (#12884).
- `retro`: "Keep only durable findings" gains a fourth test, so a list of observed cases says how a later session recognizes an unlisted case and never calls unlisted cases the reader's own doing; each recommendation makes one change for one finding (#12884).
