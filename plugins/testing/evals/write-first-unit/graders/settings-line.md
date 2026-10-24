---
type: regex
pattern: 'first_test`?\s*[=:]\s*`?unit`?\s*\(`?[^)\n]*docs/conventions/testing\.yaml`?\)'
---

Passes when the final reply names `first_test` as `unit` and `docs/conventions/testing.yaml` as
the layer that set it, in the Settings line's `key=value (source)` shape.
