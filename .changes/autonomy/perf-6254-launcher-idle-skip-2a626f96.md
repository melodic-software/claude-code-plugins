---
bump: patch
---

### Changed

- **The lane-stop gate's Stop row no longer starts bash in a session with no gate configured.** The launcher now makes the script's own pre-filter test first: it runs the gate when `lane_stop_gate_arm_id` or `lane_stop_gate_enabled` is set, or when the user settings beside a plugins/cache install or a managed settings file mentions `lane_stop_gate`. An armed lane is never skipped, and the script keeps its own check. Shared `exec-bash.mjs` synced.
