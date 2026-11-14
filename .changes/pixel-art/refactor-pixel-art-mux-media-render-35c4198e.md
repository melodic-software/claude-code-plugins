---
bump: patch
---

### Changed

- `capture.py` muxes a scene's audio into `scene.webm` through the shared media library's `pixel-art-webm` encode profile; the video is still copied as recorded and the looped audio encoded as Opus, so the output is unchanged.
