---
bump: patch
---

### Fixed

- run simulation's level read and store reads as single, absolute calls

  read-verification.sh runs alone as its own Bash call, and the run-state
  store and reference files are read with the Read tool, so no command
  chains a cd into the skill with a listing of the plugin data directory.
