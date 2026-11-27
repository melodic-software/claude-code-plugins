---
bump: none
---

### Changed

- The babysit-prs floor tests pin the floor's new rows for the architecture-scan lane: one `gate` row, `.github/workflows/maintenance-scan-architecture.yml`, because that workflow holds credentials, and six `enforcement` rows, the lane's `model-tools.json`, `file-findings.mjs`, `gate.mjs`, `lane.mjs`, `prepare-working-tree.sh` and `prompt.md`, because they set what the unattended scan may run and file. Only test pins change, so nothing ships.
