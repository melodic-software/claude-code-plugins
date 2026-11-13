---
bump: major
---

### Changed

- **Breaking:** `/multi-agent:audit-defaults` now reads the `verification` level (`lib/read-verification.sh`, team file `<home>/multi-agent.yaml` at the default branch) and passes it to the `drift-audit` workflow. At the default `light`, and at `off`, the workflow dispatches no skeptic, reports every finding `unverified`, and proposes no diff. Set `verification: standard` to restore the skeptic panel.
- `scripts/resolve-roles.sh` passes over the `verification` keys in every layer, and `/multi-agent:setup apply` writes them to the team layer only.
