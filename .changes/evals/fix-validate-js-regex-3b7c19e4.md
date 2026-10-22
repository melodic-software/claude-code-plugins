---
bump: patch
---

### Fixed

- `/evals:validate` now FAILs a regex pattern that only Python reads (`\A`, `\Z`, `\z`, a possessive quantifier, an atomic group, a `(?P<` group, a `(?#` comment, a `(?(` conditional), naming the grader and the token, and, where `node` is on PATH, compiles each regex grader and grades its samples with JavaScript's `RegExp` and fails when the result differs from the expected sort. The token check leaves `\u{41}+`, `\p{L}+` and a `\A` inside a character class alone.
