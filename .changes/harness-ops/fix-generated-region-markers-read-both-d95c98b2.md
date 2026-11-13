---
bump: patch
---

### Fixed

- `audit-native-overlap`'s `overlap.py generate` and `self-check` read a native-surfaces view fenced by either `<!-- native-surfaces:start -->` / `<!-- native-surfaces:end -->` or the `<!-- BEGIN GENERATED: native-surfaces. ... -->` / `<!-- END GENERATED: native-surfaces -->` form the ai-slop audit skips, and regenerate the block inside the form the view carries. A view with both forms, or with a missing, reversed or repeated marker, fails naming the defect and is left unchanged. A new view still gets the start/end form.
