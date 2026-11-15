---
bump: minor
---

### Added

- The handoff save-point's "Environment to re-establish" section writes the restore entry `/plugin-profiles:profile status` prints when that skill is available, and no profile entry otherwise.
- Eval case `wf-disabled-plugin-takes-fallback`: wrap-up takes the retro fallback when the corrections plugin is installed but switched off.

### Changed

- Optional calls to another plugin's skills are gated on that plugin being enabled, so a plugin that is installed but switched off takes the documented fallback, per the seam-phrasing contract. This covers the save-point's suggested-skills slot, `orient`'s timeline hand-off and the workflow skill's cloud-route docs read.
