---
bump: patch
---

### Fixed

- A handoff job's log now shows the decision: `handoff-evidence.sh` prints one line naming each settled fact and the read count, such as `handoff evidence: posted=false allowed=true (1 read)`, before it exits successfully (`.github/scripts/lib/handoff-evidence.sh`).
