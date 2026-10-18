---
bump: minor
---

### Changed

- The `plugins` skill is now model-invocable, so the model can run `sync`, `audit` or `converge` when the user asks for one. Its description states it runs only on the user's request. `converge` keeps its per-plugin confirm and its autonomous-session abort, and the `install_new: all` count-and-confirm guard is unchanged.
