---
bump: minor
---

### Added

- **Several repositories in one run.** `/attribution:audit` now accepts the target-scope forms (`--repo`, `--repos-from`, `--owner`, `--fleet`, `--skip`) and runs `audit`, `fix` or `sweep` once per repository. Each script reads that repository's tree and config. Findings carry their `owner/name`. The findings file, the sweep ledger and each pull request stay per repository. Prose that one repository copied from another in-scope repository is reported, report-only, as an in-estate copy that names the owning repository's file as its pointer target. With no target form the skill behaves as before. The plugin now ships `reference/target-scope.md`, a generated copy of the contract.
