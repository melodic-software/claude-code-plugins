---
bump: patch
---

### Changed

- `/coupling:reduce`'s rung 1 (de-globalizing shared mutable state) now says that instructions and conventions are not concurrency control: a rule telling writers to take turns guards nothing at run time, so a write target that must stay shared needs a lock, a phased order or a single writer (pstack's `separate-before-serializing-shared-state` principle) ([#12147](https://github.com/melodic-software/claude-code-plugins/issues/12147)).
