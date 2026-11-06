---
bump: patch
---

### Fixed

- run distill's progress-key script and `unzip -l` as single Bash calls

  The progress-key command and the EPUB entry listing each run alone, and the
  plugin data state and EPUB cache are checked with Glob or Read, so no command
  chains a listing of the plugin data directory with other commands.
