---
bump: minor
---

### Added

- **secret-pattern-detection:** `secret_pattern_detection_allowed_roots`, comma-separated absolute directories. A Write, Edit or NotebookEdit that holds a token is not blocked when its target's real path is strictly under one. An entry that is relative, empty, UNC, holds a glob character, a line break or a `..` component, is not an existing directory, or resolves to a filesystem root, a home directory or a directory holding one grants nothing, and with no usable home no entry grants. A link under a root that points outside it, a target spelled with a `.` or `..` segment, and a file with a second hard link are still scanned. Empty by default.
- **secret-pattern-detection:** `secret_pattern_detection_skip_gitignored`, off by default. When `true`, a Write, Edit or NotebookEdit that holds a token is not blocked when the repository holding the target reports it ignored, asked from the target's nearest existing directory, so a session started at home is covered too. Tracked files, files in no repository and symlinks are still scanned.
- With neither option set, the hook starts no extra process; with one set, the target is resolved only once the scan has found a token. Neither option applies to the GitHub MCP write lane or to the `pre-commit-content` git hook, which still judges a force-added file where that hook is installed.
