---
bump: patch
---

### Changed

- `babysit_verify_evidence.py lane-room` no longer runs the full post-merge check when the only reason the gate would not reuse the run's answer is `demotion-changed`, which any issue the lanes App opens and triage then edits sets. It reads the demotion records alone (`read_demotion`) and keeps the answer when they read as the answer recorded them; a demotion that turned active or moved still runs the full check, so a real demotion still holds the rung off. `shared_refusal` now checks the demotion last, so `demotion-changed` is reported only when nothing else refuses: a lane merge the answer does not count reports `new-merge:#<n>` first.
