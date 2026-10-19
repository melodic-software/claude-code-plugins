---
bump: patch
---

### Fixed

- `video-digest` `run-watch.js` now removes its temp video, frame and sheet directories when SIGINT or SIGTERM interrupts a watch before `watch.json` records them, then exits `130` or `143`. On POSIX the interrupt kills each child's whole process group, so a yt-dlp ffmpeg grandchild ends too; on Windows only direct children are killed. Cleanup runs once, and the handlers are removed when the run ends.
