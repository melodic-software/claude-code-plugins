---
bump: patch
---

### Fixed

- **The `map-refreshes-each-control-skill` and `map-reports-legacy-upkeep-branch` eval cases state a clean working tree in the prompt.** A stray file in the eval workspace, such as a `.gitconfig`, no longer counts as an untracked change that blocks the refresh, and each scaffold keeps `.gitconfig` out of `git status`. Each case's description now also says a run needs `--scaffold`. Without that flag the workspace stays empty and both cases score near zero.
