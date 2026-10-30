---
bump: patch
---

### Changed

- `/planning:interview` now runs a scope-cut round before it recommends `/planning:wayfind` for an effort plainly too big for its budget. For each capability it asks or applies the Must test (if this is not delivered, is the effort cancelled or worked around?) and recommends a MoSCoW bucket, keeping Must to about 60% of the effort or less. The rest goes to later work, or to wayfind once the fog trigger holds. The rule lives in the interview's `context/composition.md`, with a pointer from `context/routing.md`, and the eval case `interview-scope-cut-moscow` covers it. ([#11192](https://github.com/melodic-software/claude-code-plugins/issues/11192))
