---
bump: minor
---

### Added

- `/architecture:principles` answers module-design vocabulary questions (module, interface, implementation, seam, adapter, depth, leverage, locality, and the checks built on them), and other skills load it by name. `/architecture:improve` reads its terms from there.

### Changed

- The vocabulary's basis names the source of each term: Ousterhout for module, interface, implementation and depth; Feathers for seam; Cockburn's ports and adapters for adapter. Leverage, locality, the deletion test and the two-adapter check are marked as our own.

### Fixed

- The deepening lens's hot-spot step reads changed paths with `git log --name-only` and leaves out bot-authored commits; `git log --oneline` printed no paths to rank.
