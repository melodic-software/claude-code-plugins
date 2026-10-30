---
bump: patch
---

### Changed

- `/verification:confirm` refreshes the feature a change touched inside a control-skill module, not the module as a whole: a hub match on a module `README.md` is resolved through that README's `## Sub-features` index lines to the `<module>/<feature>` id.
