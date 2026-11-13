---
bump: major
---

### Changed

- `/planning:plan` close-out's fallback container query names the work-items container label's new default, `spec-container`.
- `/planning:wayfind` creates a map with the label `wayfind: map` and without the work-items container label, lists open maps by `wayfind: map`, and checks only the `wayfind:` labels and `needs-human` at chart entry. A map that carries only the container label (`work-map` or a remapped `tracker.config.container_label`) is no longer found as a map: add `wayfind: map` to each open map before upgrading.

### Removed

- `skills/wayfind/scripts/container-label.sh` and its test: wayfind no longer reads `tracker.config.container_label`.
