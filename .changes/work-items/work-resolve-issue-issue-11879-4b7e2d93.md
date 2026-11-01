---
bump: minor
---

### Added

- `skills/setup/scripts/migrate-binding.sh` moves a legacy `.work-item-tracker.json` under `tracker:` in `<home>/work-items.yaml` and a legacy `.work-item-tracker.local.json` under `tracker:` in `<home>/work-items.local.yaml` (#11879). It keeps every other setting already in those files, checks that each copy reads back through the seam as the same binding, and removes a JSON file only after that check passes. When a target already sets `tracker:` or no convention home applies, it changes nothing and says why. `migrate-binding.test.sh` covers the migration and each refusal.

### Changed

- `/work-items:setup apply` writes the binding to the `tracker` key of `<home>/work-items.yaml` and the personal overlay to `<home>/work-items.local.yaml`, per ADR 0075 fix 11. It runs the migration first when the project root still holds a JSON binding or overlay, and announces each file it moved and removed. The overlay's ignore rule is now `<home>/**/*.local.*`.
- `/work-items:setup check` reports a FAIL for a repository still on `.work-item-tracker.json` or `.work-item-tracker.local.json`, with `/work-items:setup apply` as the remediation. It reads the YAML binding and overlay.
- The setup evals name the YAML files, and a new case expects `apply` to migrate a legacy JSON binding.
