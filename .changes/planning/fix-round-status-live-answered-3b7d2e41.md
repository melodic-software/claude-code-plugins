---
bump: patch
---

### Fixed

- `round.sh status` counts the live questions the page meter counts. Each group line now reads `N of M live answered; K archived` instead of counting archived questions as closed, and an accepted row with an unticked commitment gets its own `accepted, to confirm:` line. `status --json` gains `live`, `answered` and `toConfirm` per group; `closed` is unchanged.
