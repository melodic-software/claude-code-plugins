---
bump: patch
---

### Fixed

- `audit-native-overlap`'s `overlap.py generate` and `self-check` read a native-surfaces view fenced by either `<!-- native-surfaces:start -->` / `<!-- native-surfaces:end -->` or the `<!-- BEGIN GENERATED: native-surfaces. ... -->` / `<!-- END GENERATED: native-surfaces -->` form the ai-slop audit skips, and regenerate the block inside the form the view carries. A view with both forms (the message lists the marker lines found), a missing, reversed or repeated marker, or a `BEGIN GENERATED: native-surfaces.` line whose instruction text differs from the expected one (the message prints the expected line) fails and is left unchanged, as does a run whose generated content would hold a marker line. A new view still gets the start/end form.
