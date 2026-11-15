---
bump: patch
---

### Changed

- Skill instructions for course-digest, distill, docpage-digest, map-corpus and video-digest use
  plain emphasis instead of capital letters, and drop notes about how a rule came about.
- Corrected facts the instructions had wrong: the screenshot file names and folders the
  extractor writes, the referer header it sends, where key-frame PNGs live, and the claim-inventory
  phase number. Version-dependent tool facts (Chrome remote debugging, ffmpeg `-ss` and its
  `whisper` filter, the plugin variables) now point at their upstream pages.
