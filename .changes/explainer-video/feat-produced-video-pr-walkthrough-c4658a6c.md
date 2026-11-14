---
bump: minor
---

### Added

- A stills renderer: `/explainer-video:produce` turns a `storyboard.json` into one narrated video of held
  3840x2160 frames with burned captions, chapters, a contact sheet and a `manifest.json`, checked against a luma
  SSIM floor of 0.999 per frame and scanned for secrets and machine data before anything renders. New settings:
  `stitcher` and `frame_stylesheet` (read from the default branch only), `upload_limit_mb`. Playwright for Python joins the requirements;
  its Chromium downloads on the first stills render.
- A shared media library (`media_*.py`, `media_templates/`) vendored from `lib/media-render`: frame capture through
  Playwright for Python, frame templates, storyboard timeline, captions, encode profiles, loudness, verification,
  upload-size splitting, contact sheets and a secret and machine-data scan.

### Changed

- `render.py` muxes, normalizes loudness and builds captions through the shared library; output is unchanged.
