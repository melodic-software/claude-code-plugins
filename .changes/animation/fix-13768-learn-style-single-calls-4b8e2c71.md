---
bump: patch
---

### Fixed

- run learn-style's scripts as single Bash calls and read `style.json` with Read

  Each `pydeps.py run` call runs alone, with no `cd`, `--help` or other command
  chained to it; the skill never probes the host Python or its packages, never
  runs `pydeps.py install`, and never lists the plugin data directory, and it
  reads a pack's `style.json` with the Read tool instead of `python3 -c`.
