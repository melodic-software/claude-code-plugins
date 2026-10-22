---
bump: patch
---

### Fixed

- `/playwright:demo-video` quality control no longer crashes on the last frame of a video or shows the next frame in about one contact-sheet tile in three. It seeks half a frame before each frame, and a short ffmpeg read now fails with an error naming the frame index and its timestamp.
