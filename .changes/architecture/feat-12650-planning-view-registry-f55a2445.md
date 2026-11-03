---
bump: patch
---

### Changed

- Shared `view-builder.mjs`, `view-settings.mjs` and `view-registry.mjs` synced where this plugin carries them: the view-kind registry and `render(laneId, kind, record)`, the planning lane's design kind and shipped `artifact` default, and the resolver output's `page` and `publishes` fields (#12650). The shared `reference/rendered-view.md` copy carries the planning section's one-call build and design view; no other change to this plugin.
