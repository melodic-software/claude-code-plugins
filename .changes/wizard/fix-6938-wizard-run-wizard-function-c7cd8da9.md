---
bump: patch
---

### Fixed

- A generated wizard no longer re-runs earlier steps when its script is edited while it runs. bash reads a script from a file offset as it goes, so an in-place edit that shifted the bytes made it run already-finished stages again. The stages now sit inside a `run_wizard` function that ends in `exit`, and the script's last line calls it, so bash parses the whole file before the first prompt.
