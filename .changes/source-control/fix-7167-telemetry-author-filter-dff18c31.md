---
bump: patch
---

### Fixed

- only adopt babysit-loop telemetry comments the lane wrote

  The telemetry upsert matched any comment opening with the public
  sentinel, so an outsider's lookalike with a lower id became canonical.
  The lookup and the lowest-id reconcile now consider only comments
  written by the script's own write identity (the `gh api user` login,
  or `<app-slug>[bot]` under an App token via `--app-slug`), and a new
  `--read` mode gives re-anchor the same filtered read (#7167). A create
  that lands under another login (a wrong `--app-slug`) exits 5 instead
  of posting a fresh comment every cycle.
