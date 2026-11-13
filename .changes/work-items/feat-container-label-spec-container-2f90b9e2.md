---
bump: minor
---

### Changed

- The shipped default for `tracker.config.container_label` is now `spec-container`, the label that marks a `/work-items:decompose` spec container. `list-frontier`, `/work-items:ship` discovery and `/work-items:decompose` container publishing use it when the key is absent or empty. A repository whose containers still carry only `work-map`, the earlier default, sets `tracker.config.container_label: work-map` until it relabels them.
- A `/planning:wayfind` map is known by a label starting with the wayfind prefix (`tracker.config.wayfind_label_prefix`, default `wayfind:`), not by the container label. `/work-items:track add` gives such an item no `category:general` default and no `needs-triage` floor, `/work-items:triage` leaves it out of the attention view, `/work-items:work-loop` never lets an open map or decision item gate a drain exit, and the decomposed-parent close leaves a map to `/planning:wayfind`. `reference/label-taxonomy.md` "Maps and containers" states the rule.
