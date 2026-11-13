---
bump: patch
---

### Fixed

- `/planning:wayfind` reads the wayfind label prefix (`config.wayfind_label_prefix`) and the
  human-gated label (`config.role_labels.human-gated`) from the repository's tracker binding and
  builds every label it writes or queries from them. A repository that remapped either no longer
  gets map items under the old prefix, which `/work-items:work`'s frontier stopped excluding.
- Wayfind routes `design` items to the event-storming skills and `prototype` items to the
  prototype skills only when those plugins are enabled, falling back to `/planning:design` and an
  inline prototype.
