---
bump: patch
---

### Changed

- The tracker binding's per-user layer, `work-items.local.yaml` (or the legacy
  `.work-item-tracker.local.json`), is now called the personal override in the setup skill, the
  tracker CONTRACT, the README, the schema, the evals and the tracker scripts and their tests.
  The setup reference that held the ignore probes, `overlay-ignore-probes.md`, is renamed to
  match. `lib/binding.sh` names its helpers `wit_override_path` and `wit_find_override`, and its errors
  say "personal override" and "non-overridable".
- `migrate-binding.sh` labels its second output line `override:`. It was `overlay:`.
