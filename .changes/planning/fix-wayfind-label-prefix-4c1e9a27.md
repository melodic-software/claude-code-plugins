---
bump: patch
---

### Fixed

- `/planning:wayfind` reads the wayfind label prefix (`config.wayfind_label_prefix`) and the
  human-gated label (`config.role_labels.human-gated`) from the binding file the tracker reads (the
  `WORK_ITEM_TRACKER_BINDING` file, else `work-items.yaml` in the bound convention home) and builds
  every label it writes or queries from them. A repository that remapped either no longer
  gets map items under the old prefix, which `/work-items:work`'s frontier stopped excluding.
