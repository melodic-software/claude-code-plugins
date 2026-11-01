---
bump: minor
---

### Changed

- `/work-items:setup apply` writes the tracker binding under the `tracker` key of `<home>/work-items.yaml` and the personal overlay under `tracker` in `<home>/work-items.local.yaml`, and makes sure a `.gitignore` rule covers the new overlay path (#11879). It keeps every other key in `work-items.yaml`.
- When only the legacy `.work-item-tracker.json` binds a repository, `apply` copies it and its `.work-item-tracker.local.json` overlay into those files with the new `skills/setup/scripts/migrate-binding.sh`, says so, and leaves both JSON files unchanged, because babysit-prs, the autonomy plugin's resolve-prerequisites and the work, triage, attend-queue and track preflights still read only them. The script reads each copy back through the seam before writing it.
- `/work-items:setup check` reports a repository whose binding exists only in the legacy JSON file, and names any value that differs when both files bind it.
