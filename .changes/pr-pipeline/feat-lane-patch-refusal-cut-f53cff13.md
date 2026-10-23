---
bump: minor
---

### Changed

- Lane patches reach review outside workflows and settings. Every [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json) row now refuses `github-workflows` (`.github/workflows/**`, which the lane token cannot push), `codeowners` (a `CODEOWNERS` file at the root, in `.github/` or in `docs/`), `gitmodules`, `settings`, `symlink`, `gitlink` and `rename-into-refused`, plus `backslash` on every row. The rest of `.github/`, `.claude/`, the root `.mcp.json`, agent instruction files, plugin hooks, monitors and bin, and an executable bit the patch sets now reach the branch and its review.
- `address-feedback` hands a pull request to a person as `feedback-protected-path` only when it changes `.github/workflows/**`, and a kept thread's scope may now hold a path elsewhere under `.github/`. `pr-merge` clears that reason once the pull request changes nothing under `.github/workflows/`.
- `resolve-conflicts` escalates `protected-path-conflict` only for a conflicted workflow, `.gitmodules` or `settings*.json`; a conflicted `CLAUDE.md`, `.claude/` or `.mcp.json` goes to the model, and `post.sh` keeps the resolution it staged. It escalates `unexpected-path-staged` only for a symlink, gitlink, backslash path, `.gitmodules`, settings file or `CODEOWNERS` change outside the conflicts; any other change the model stages is committed and reaches review.

### Removed

- The `github`, `claude`, `mcp-config`, `new-executable` and `instruction-path` refusals, and the rule that a `script-exec-bit` row must refuse `instruction-path`.
