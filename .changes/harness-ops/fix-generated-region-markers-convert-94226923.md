---
bump: patch
---

### Changed

- `audit-native-overlap`'s `overlap.py generate` writes a new native-surfaces view with the `<!-- BEGIN GENERATED: native-surfaces. ... -->` / `<!-- END GENERATED: native-surfaces -->` markers the ai-slop audit skips. A view that carries the older `<!-- native-surfaces:start -->` / `<!-- native-surfaces:end -->` markers is still read and regenerated in that form.
