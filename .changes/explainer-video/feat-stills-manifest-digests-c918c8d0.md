---
bump: patch
---

### Security

- `stills.py` binds every file `manifest.json` lists to its final bytes: the video, each chapter
  part and each contact sheet carry a `sha256`, and each screenshot entry is now
  `{path, sha256, sidecar, sidecar_sha256}`, with the image and the sidecar text the scan read
  copied into the output folder, so an uploader can refuse any file whose bytes changed after the
  scan.
