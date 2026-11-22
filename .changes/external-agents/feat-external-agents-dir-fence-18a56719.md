---
bump: minor
---

### Added

- `external-agents run <antigravity|codex>` takes a repeatable `--add-dir <absolute dir>` on a write run, mapped to each CLI's own `--add-dir` through its provider record, so a task can write a named directory outside its workspace. It is refused with exit 2 on a read-only run, a review, a resumed Codex thread, a relative path or a directory that does not exist. The job records `add_dirs` and `fence`, and `status <job>` prints both.
- `--unsandboxed auto` opts one antigravity write run into agy's `--mode auto`; on such a run the command reads agy's log for the run and, when it shows auto mode was applied, says so instead of reporting agy's auto-mode warning as a fallback. Codex declares no opt-in, so `--unsandboxed` is refused for it.

### Changed

- An antigravity write run is fenced by default: `--mode accept-edits` with agy's terminal sandbox on, sandboxed commands allowed and no access beyond the workspace, so a command that asks to leave the sandbox is refused and recorded `blocked-by-mode`. The `antigravity` and `codex` skills tell the delegating agent to decide every extra writable directory, and for agy whether an out-of-sandbox command is needed, before the run, and to name them in the prompt.
