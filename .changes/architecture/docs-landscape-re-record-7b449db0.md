---
bump: patch
---

### Fixed

- `map-landscape`'s reference-edge collector skips test files in any language (`*.test.*`,
  `*.spec.*`) and `*.vectors.json` tables, treats `other` and `eval-fixture` as placeholder
  owners, and rejects an owner holding a dot, so test names such as `o/r` and an elided
  `github.com/.../issues` no longer become systems in the landscape.
- `map-landscape`'s portfolio collector lets only a root-level runtime-scope `requirements*.txt`
  claim the Python runtime, so one component's requirements file no longer reports a shell
  repository as Python or hides its development-scope CI requirements.
