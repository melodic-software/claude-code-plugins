---
bump: patch
---

### Changed

- A module `README.md` that the hub indexes in place of its features now lists each feature under `## Sub-features` as a full index line (path, entry-point count and `sources` globs). A caller that matches the module's hub line reads those lines to find the exact feature a changed file touches, and `/app-control:map refresh` keeps both sets of lines true. Each feature's own `README.md` is the source of truth for its entry points; the module `README.md`'s copy is rewritten from the features when they disagree.
