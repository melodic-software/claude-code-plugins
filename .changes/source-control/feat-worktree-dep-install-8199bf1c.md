---
bump: minor
---

### Added

- `worktree-create.sh` runs `npm ci` in a new worktree that has a `package-lock.json`, so the first commit's pre-commit hooks find `node_modules/.bin`. A missing npm, a failed install, or the 45-second cap (`WORKTREE_CREATE_DEPS_CAP_SECONDS`) warns on stderr and leaves the exit code unchanged.
