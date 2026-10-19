---
bump: patch
---

### Fixed

- The inventory extraction resolves a description or menu description that a bundled skill reads through an arrow over a mode table (`()=>s().description()`, where `s` returns `<table>[<expr>??"<key>"]`), so the `design` skill no longer lands in `integrity.undetermined.description_unresolved` (#7987).
