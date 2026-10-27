---
bump: patch
---

### Fixed

- enable-auto-merge no longer holds a lanes App pull request on a hold path once a person on the trusted-actor list approved its current head, the same `pathLifters` rule `ci-status` lifts that hold by; its other checks then decide. An approval of an older head, an untrusted reviewer's approval, or a newer request for changes lifts nothing, and a hold-path list or file listing that could not be read, or one too long to check, still holds (`.github/scripts/pr-merge/enable-auto-merge.mjs`). The gate's risk score lifts the same paths' `high-path:` reasons on that approval, so such a pull request now arms end to end (source-control's `path_lifters`).
