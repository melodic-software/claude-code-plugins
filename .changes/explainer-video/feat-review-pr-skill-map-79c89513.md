---
bump: minor
---

### Added

- The stills renderer's `diagram` moment takes an optional `layout`: `flow` (the default) joins its nodes with arrows as before, while `stack` (layers, top first) and `group` (side by side, under an optional `center` heading) draw no arrows, so a hub, a set of layers or a comparison is no longer shown as a sequence.
