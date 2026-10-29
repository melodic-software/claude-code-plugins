---
bump: patch
---

### Fixed

- README Hook section: the note on why the settings checkpoint row carries no `if` filter now names the cause the Claude Code 2.1.285 probe on Windows found. In a hook `if`, an `Edit(...)` rule does not match a Write tool call at any path tested, while `Write(...)` and `Edit(...)` rules each match absolute paths outside cwd for their own tool. The note no longer blames the skip on an absolute path outside the working directory. The row stays unconditioned (#3680).
