---
bump: minor
---

### Added

- A compact-focus hook prints the session's focus file before every compaction, manual or
  automatic, so the summary keeps the active `/goal` condition, the resumed handoff file and the
  step-away task file. A typed `/goal` updates the file; `/goal clear` and its aliases remove the
  goal. `scripts/focus.py` (`set`, `clear`, `print`, `hook`) is the only reader and writer of the
  focus folder, and `/session-flow:step-away` records its task file there at launch and clears it on
  return.
- `compact_focus_enabled` (default on) turns the hook and every focus write off. The user's own
  value wins over `docs/conventions/session-flow.yaml`.
