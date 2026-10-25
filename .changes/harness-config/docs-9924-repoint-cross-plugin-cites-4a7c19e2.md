---
bump: patch
---

### Changed

- **The effort-pin check and the conflict criteria no longer cite another plugin's skill folder.** `check-effort-pins.sh` finds lane-config pins by their JSON `"effort"` key in any skill's `context/*.md`, not by a path into another plugin's skills folder, so a lane config is still listed where it lives and the check never depends on another plugin's internal layout. The conflict criteria's worked example names `/repo-hygiene:clean` instead of a path to its `SKILL.md`.
