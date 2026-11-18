---
bump: patch
---

### Changed

- `worktree-create.sh` runs `npm ci` once per distinct `package-lock.json` into `<root>/.npm-seed/<sha256>` and hard-links that `node_modules` into each new worktree, so worktrees on one lockfile share one copy on disk. Without `flock`, a SHA-256 tool or a working `cp -al`, or with `WORKTREE_CREATE_NPM_SEED=0`, it runs `npm ci` in the worktree as before. Seeds unused for `WORKTREE_CREATE_NPM_SEED_DAYS` (default 14) are removed.
