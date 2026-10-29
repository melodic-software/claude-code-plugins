---
bump: none
---

Adds a test for the `/playwright:demo-video` contact-sheet frame grab that runs where numpy, Pillow, ffmpeg and ffprobe are installed: grabbing a frame past the end of a real 339-frame video fails with an error naming the frame and its timestamp, not Pillow's `not enough image data`. The script is unchanged.
