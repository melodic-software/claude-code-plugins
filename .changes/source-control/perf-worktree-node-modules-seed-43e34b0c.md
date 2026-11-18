---
bump: patch
---

### Changed

- `worktree-create.sh` runs `npm ci` once per distinct install into `<root>/.npm-seed/<key>`, makes the seed read-only, and hard-links that `node_modules` into each new worktree, so worktrees on one lockfile share one copy on disk. The key covers the lockfile, `package.json`, `.npmrc`, the Node ABI, `NODE_ENV` and `npm_config_*` variables. It runs `npm ci` in the worktree as before without `flock`, `node` or a working `cp -al`, for a package with workspaces, install lifecycle scripts or `file:`/`link:` dependencies, when the seed install fails, or with `WORKTREE_CREATE_NPM_SEED=0`. Seeds unused for `WORKTREE_CREATE_NPM_SEED_DAYS` (default 14) are removed.
