---
bump: minor
---

### Changed

- The context zones are renamed: `smart` is now `light`, `acceptable` is `moderate` and `dumb` is
  `heavy`, in the resolver's output, the module's lines, toasts and band row, the status tool, the
  snapshot's `zone` and `bands` keys, and telemetry. Band edges and the "(N of 3)" rank are
  unchanged.
- `zones.json` keys are renamed to `light_max_used_percentage`, `moderate_max_used_percentage`,
  `light_max_tokens` and `moderate_max_tokens`, and `actions` takes `light`, `moderate` and
  `heavy`. `/context-guard:setup apply` renames the old keys.

### Deprecated

- For this release, `zones.json` still reads the old key names and the old `actions` zone names
  as the new ones, the new name winning when both are set.
