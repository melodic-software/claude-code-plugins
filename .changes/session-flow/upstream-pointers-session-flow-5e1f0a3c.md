---
bump: patch
---

### Fixed

- The handoff gotchas no longer claim the scheduled-tasks page says a fresh conversation clears every session task; the re-arm rule now checks which loops came back before re-arming, so a loop a resume restored is not scheduled twice, and points at the live Limitations section. The gather reference cites the final probe comment on the `$`-expansion guard and stops saying bare `$HOME` is the only form that passes. The save-point record and refusal message stop labeling the Remote Control bridge id with a stale form, and the hop-chain harness comment keeps the `dontAsk` regression as our own observation on CLI 2.1.260. The handoff gotchas attribute the start-of-message command rule to the live Commands page instead of calling it ours.

### Changed

- Restated upstream specifics (skill-listing drop order, plugin data dir layout, native command descriptions and version notes, background-session inheritance, auto-mode categories, MCP transports, the Read tool cap) are replaced with pointer records to the exact live docs section, each with an as-of date and recheck trigger. The `native-*` reference files move to the `Decision | Pointer | As of | Recheck when` table.
