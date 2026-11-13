---
bump: minor
---

### Added

- A shared media library (`media_*.py`, `media_templates/`) vendored from `lib/media-render`: frame capture through
  Playwright for Python, frame templates, storyboard timeline, captions, encode profiles, loudness, verification,
  upload-size splitting, contact sheets and a secret and machine-data scan.

### Changed

- `render.py` muxes, normalizes loudness and builds captions through the shared library; output is unchanged.
