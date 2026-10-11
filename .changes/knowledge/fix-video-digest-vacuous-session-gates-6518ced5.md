---
bump: patch
---

### Fixed

- video-digest's `session-visual-coverage` and `session-synthesis-depth` outcome checks, and `list-promotion-candidates.js`, now fail with the required session format when `research/claim-inventory.md` parses to no session, instead of passing over zero sessions. Boundary stamps may be `[h:mm:ss]` as well as `[m:ss]`, and Phase 2 documents the `## <n>. <name>` plus `**Boundary:**` shape with an example.
