---
bump: minor
---

### Deprecated

- `filing_posture` in `docs/conventions/bugs.yaml` and the other bugs layers. Set it in
  `docs/conventions/work-items.yaml` instead. For one release `/bugs:scan --track` still reads it
  from the bugs layers, with a notice, when the work-items file does not set it; the work-items
  value wins when both are set. `/bugs:setup` reports a bugs-layer value as deprecated and no longer
  writes the key.
