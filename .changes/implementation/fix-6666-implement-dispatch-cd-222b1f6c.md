---
bump: patch
---

### Fixed

- **`/implementation:implement-dispatch` drops the `cd <worktree> && <command>` exception.** Brief item 8 and the worktree-cwd gotcha now send a working-directory-sensitive build, test or lint command through its own directory flag (`make -C`, `npm --prefix`) or the wrapper's absolute path, and leave a command with neither to the orchestrator's main-side gate. A `cd` into a worktree outside the session's working directories prompts, so the exception brought back the denial the literal-path rule avoids (#6666).
