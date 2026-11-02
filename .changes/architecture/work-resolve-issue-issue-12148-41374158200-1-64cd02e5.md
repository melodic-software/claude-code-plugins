---
bump: patch
---

### Changed

- The deepening scan of `/architecture:improve` now treats reader load as two axes: the layers a reader must trace and the state a reader must hold. Line count is only a proxy for either, so it never counts as evidence of shallowness. The scan also gains a signal for an invariant that several callers re-check when the module that first makes the value could enforce it once in its interface. Both come from pstack's `minimize-reader-load` principle ([#12148](https://github.com/melodic-software/claude-code-plugins/issues/12148)).
