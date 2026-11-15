---
bump: patch
---

### Changed

- `shared/web/proto-pin.js`, the generated copy of `lib/ui-feedback/proto-pin.js`, gains the
  notes host's region and text-selection modes, a view snapshot on each pin, and a data-control
  log. The prototype page sends none of the new messages and reads only `selector`, `rect` and
  `label` from a pin, so it behaves as before.
