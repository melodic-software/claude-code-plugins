---
type: regex
pattern: 'first_test`?\s*[=:]\s*`?user-flow`?\s*\(`?[^)\n]*docs/conventions/testing\.yaml`?\)'
---

Passes when the final reply names `first_test` as `user-flow` and `docs/conventions/testing.yaml`
as the layer that set it, in the Settings line's `key=value (source)` shape.
