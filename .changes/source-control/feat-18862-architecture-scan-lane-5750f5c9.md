---
bump: none
---

### Changed

- The babysit-prs floor tests pin the floor's new rows for the architecture-scan lane: one `gate` row, `.github/workflows/maintenance-scan-architecture.yml`, because that workflow holds credentials, and fourteen `enforcement` rows, because they set what the unattended scan may run and file: the lane's `model-tools.json`, `file-findings.mjs`, `gate.mjs`, `lane.mjs`, `prepare-working-tree.sh` and `prompt.md`, and the plugin helpers its tool list allows with what they source or import (`plugins/improvement/lib/state-key.sh`; `plugins/architecture/lib/resolve-convention-home.sh`, `read-verification.sh`, `default-branch-file.sh`, `config-root.sh`, `config-cascade.mjs`, `yaml-subset.mjs`; `plugins/architecture/skills/improve/scripts/improve-settings.mjs`). Only test pins change, so nothing ships.
