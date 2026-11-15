---
bump: minor
---

### Added

- `/prototype:explore-directions` says where a notes session's files go: the distilled notes and
  screenshots to the memory slice, and, for a named map item, those files and the mockup page to
  the item's folder on the map's dossier branch, pushed only after the repository's secrets and
  machine-data check passes, with `not pushed: <reason>` in the reply otherwise. Real-stack
  screenshots stay local.
- Review mode's boundaries name the local notes host as one person's element-pinned notes.
- Eval cases `ed-notes-dossier-map-item` and `ed-notes-dossier-check-fails` cover the passing and
  the failing check against a local bare remote.
