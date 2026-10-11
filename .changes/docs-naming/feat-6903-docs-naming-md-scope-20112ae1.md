---
bump: minor
---

### Added

- A `roots` entry may be an object, `{"path", "extensions", "exempt_paths"}`, that limits a root to some extensions (matched in any case) and exempts paths inside it from the basename rule unless another root claims them. The audit inventory, the emitted gate, its rule file, and `setup check` all read it. A string root is now read as a git glob, `<root>/**`, as the audit already read it, so the gate and the audit agree on a directory root and a string root naming a single file claims nothing.

### Changed

- The emitted gate folds paths for the case-collision check with one `tr` over the whole list instead of one per path, so a root holding thousands of files stays fast.

### Security

- `generate-file-name-gate` refuses a `regex` or `rule` that carries a newline. Both land on comment lines of the emitted checker, where a newline would end the comment and run the rest as shell on every CI run. It also refuses a root path or root exempt path that is absolute or has a `..` segment, which would otherwise make the emitted gate judge nothing and report a clean tree.
