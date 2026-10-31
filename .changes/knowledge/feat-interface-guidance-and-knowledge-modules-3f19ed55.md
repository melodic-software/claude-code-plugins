---
bump: minor
---

### Added

- `vendor/node-launcher/` holds the launcher, resolve hook and dependency installer both extraction packages share. Each package's `run.mjs` and `setup-deps.mjs` stays at its path and passes only its own options; a package names its install stamp, its label and whether it needs Chromium in the `setupDeps` field of its `package.json`. `/knowledge:setup apply install-deps` runs the shared `setup-deps.mjs` once per package with `--package`.
- `vendor/repo-analysis/` (0.2.0) holds the one shallow clone, hardened by default (no credential helper, no prompt, no LFS download, an isolated home, a timeout that kills the clone's process group), with an `inheritGitEnvironment` option that runs git in the user's own environment, and `clone-cli.js`, which runs the hardened clone with no install.
- `lib/gates/` holds the failure list and the heading and code-fence recognizers the docpage-digest gates, the map-corpus gates and the map-corpus node extractor share; each caller passes the options that keep its own results.

### Changed

- `/knowledge:course-digest` clones a course's companion repository through the shared clone with `inheritGitEnvironment`, so a private course repository still clones with the user's credentials and a failure still reports git's own error text.
- `/knowledge:absorb-upstream` clones a repository through `clone-cli.js` and reads a page through the plugin's `fetch-docs.sh` (generic profile, public addresses only), reading a page only when its manifest record says it was read.
- The course-digest overview names Playwright as its browser automation, and the README's revisit condition for a standalone video plugin names every vendored package `video-digest` shares.
