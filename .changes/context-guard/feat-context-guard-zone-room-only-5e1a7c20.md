---
bump: major
---

### Changed

- **Breaking:** a compaction no longer forces the zone to `heavy`. The zone reports room only, in
  the module's lines, toast, band row, status tool and snapshot; `evidence_degraded` and the
  `.compacted` marker report the compaction beside it. A reader that took a compacted session's
  `heavy` as its degraded signal reads `evidence_degraded` or the marker instead.
- After a compaction the verdict is restated once at any zone, with "compacted" beside it, such as
  `light zone (1 of 3, compacted)`, and crossings restart from that zone; the toast and band row
  show "compacted" beside any zone.
- The reader contract's marker rule changes: the marker is read beside the zone, and each consumer
  decides what it means for its own routing.
- The reader contract no longer calls the 200k row's `moderate` edge a practitioner consensus: it
  is a declared judgment default with no measured basis. Band values are unchanged.
- The options line Claude reads past `light` names `/context` for what fills the window.
