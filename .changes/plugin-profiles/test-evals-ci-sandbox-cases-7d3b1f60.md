---
bump: none
---

Removes the `setup-installs-only-after-yes` eval case: the eval sandbox mounts `~/.claude`
read-only, so the save and install it grades cannot succeed there. No skill behavior changes.
