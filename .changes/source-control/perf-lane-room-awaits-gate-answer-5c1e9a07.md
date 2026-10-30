---
bump: patch
---

### Changed

- The lane room (`babysit_verify_evidence.py lane-room --await-artifact`) no longer runs a second full post-merge check when it refuses this run's report at the same moment as the merge job. Before it reads the check again, it waits, for at most 15 polls 10 seconds apart, for the check the merge job ran itself, and takes that answer only if the same reuse rule (`settle_shared`) reuses or keeps it. Anything else falls back to the room's own check, as before. The room line reports such an answer as `"answer": "awaited"`.
