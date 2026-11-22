---
bump: minor
---

### Added

- `scripts/provision-prerequisites.sh`, the provisioning step: it installs each lockfile an ecosystem record's `requires` entry declares with an `install` object (`{manager: npm, lockfile: <path>}`) by `npm ci --ignore-scripts --no-audit --no-fund` in that lockfile's directory. It reads records from `docs/conventions/ecosystems/`, and a legacy `.claude/ecosystems/` file only for a name absent there, with a warning naming both when both exist. When no record declares any lockfile, it installs a root `npm-shrinkwrap.json` or `package-lock.json` the same way and prints a notice to declare it under `requires.<command>[].install`; that fallback ends at the ecosystem-commands contract's next major version, with the legacy-location read.

### Changed

- Worktree creation runs the provisioning step as its one install path, so its `npm ci` now runs with install scripts off. A lockfile that no record declares is installed only through the root fallback above. A repository declares its lockfiles in a record (`docs/contracts/ecosystem-commands/README.md`, "Provisioning").
