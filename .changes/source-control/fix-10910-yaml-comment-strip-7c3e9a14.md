---
bump: patch
---

### Fixed

- `babysit_risk.py` no longer drops workflow text after a space and `#` inside a quoted string or a block scalar (`run: |`). `gated_workflow` and the permission, trigger and secret backstops used to cut every line at its first space-and-`#`, so a `${{ secrets.X }}` after `echo "a #b` or after a shell comment in a `run:` block went unseen. Such a workflow now counts as a `gate` path, and adding one holds as `secret-exposure-review`. A real YAML comment still counts for nothing.
