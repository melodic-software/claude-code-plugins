---
bump: none
---

Adds a test for the `/playwright:demo-video` contact-sheet frame grab. It runs only where numpy, Pillow, ffmpeg and ffprobe are installed. On an encoded 339-frame, 30 fps H.264 test video, frames 0, 170 and 338 come out byte-identical to the frame ffmpeg selects by index. Frames 170 and 338 are 2 (mod 3), the case the old seek got wrong. The grab moves from inside `quality_control.py`'s `main()` to a module-level `grab_rgb()` so the test runs the same code. The script behaves the same.
