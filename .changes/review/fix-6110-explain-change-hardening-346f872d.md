---
bump: patch
---

### Security

- explain-change: `risk_paths` globs now match through a linear-time matcher instead of a compiled regular expression, so a star-heavy glob from a config layer no longer triggers regex backtracking: match time grows with path length times glob length rather than exponentially. A layer's `risk_paths` is invalid, and the layer below supplies it, past 64 globs or a glob longer than 256 characters. (#6110)
