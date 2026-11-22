---
bump: minor
---

### Added

- `scripts/provision-prerequisites.sh`, the provisioning step: it installs each lockfile an ecosystem record's `requires` entry declares with an `install` object (`{manager: npm, lockfile: <path>}`) by `npm ci --ignore-scripts --no-audit --no-fund` in that lockfile's directory, and nothing else.

### Changed

- Worktree creation runs the provisioning step as its one install path, so its `npm ci` now runs with install scripts off, and a `package-lock.json` no ecosystem record declares is no longer installed. A repository that wants `node_modules` in new worktrees declares its lockfile in a record (`docs/contracts/ecosystem-commands/README.md`, "Provisioning").
