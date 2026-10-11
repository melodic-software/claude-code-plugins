---
bump: minor
---

### Added

- A `roots` entry may be an object, `{"path", "extensions", "exempt_paths"}`, that limits a root to some extensions (matched in any case) and exempts paths inside it from the basename rule unless another root claims them. The audit inventory, the emitted gate, its rule file, and `setup check` all read it; a plain string root is unchanged.

### Changed

- The emitted gate folds paths for the case-collision check with one `tr` over the whole list instead of one per path, so a root holding thousands of files stays fast.
