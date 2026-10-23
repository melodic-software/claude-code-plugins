---
bump: minor
---

### Changed

- `pull-request dependency --ci` commits nothing and runs no command: it leaves a `fix` verdict's manifest change uncommitted in the working tree, and a later job with no model pushes it as one `[dependabot skip]` commit. It reads release notes with WebFetch on the hosts its preamble names, and its report names no fix commit ([`dependency-ci.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/skills/pull-request/reference/dependency-ci.md)).
