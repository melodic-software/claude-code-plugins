---
bump: patch
---

### Fixed

- `/docs-hygiene:setup` says `--check` prints only its INFO line when `docs/conventions/docs-hygiene.yaml` is absent, as the script does; it read as if per-key lines followed.
- The `setup-resolves-and-runs-the-binary` eval scaffold passes `--include=dev`: `claude plugin eval` runs a scaffold under `NODE_ENV=production`, which made npm skip the pinned `markdownlint-cli2` and failed the scaffold (#13279).
