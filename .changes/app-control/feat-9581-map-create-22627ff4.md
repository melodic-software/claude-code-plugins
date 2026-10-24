---
bump: minor
---

### Added

- `/app-control:map create` generates a project's control skill: it walks fixed discovery rows over the repository before asking anything, asks only what discovery left open (through `/planning:interview` when installed), writes the hub, feature folders, config, driver CLI and one pointer in the repository's source instruction file, then proves it once through `/app-control:drive` and checks the evidence survived and no process it started is alive. `--unattended` stops at the first open question and never guesses a safety answer. Reauthored from the create-and-prove flow of pstack's `create-verification-skill` ([cursor/plugins](https://github.com/cursor/plugins), MIT).
- The control-skill contract gains three sections: writing the driver CLI (through `/developer-experience:build-cli` when installed, else a documented script), config layered from committed `config/defaults.json` through `config/local.json`, environment variables and flags with each value's layer reported, and safety floors that ship safe (an empty recipient allowlist, one sign-in attempt per account per run, read-only production, no unattended writes) and loosen only in committed config.
