---
bump: none
---

Test-only: the babysit-prs suite now fails when an entry in the merge gate's scripts directory has the name of a standard-library module, such as `json.py`, a `logging/` package or a compiled module. Python puts that directory first on `sys.path`, so such an entry would load in place of the real module. The gate still runs without `-I` or `-P`, so its sibling imports resolve as before. Nothing a user runs changes.
