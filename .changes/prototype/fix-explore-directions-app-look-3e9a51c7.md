---
bump: patch
---

### Fixed

- `/prototype:explore-directions`: variants of an existing app's feature now keep the app's look on every host, the HTML mockup included. On the mockup, every variant inlines the app's own CSS and surrounding page and varies only the subtree under test; a per-variant visual direction applies only when no app exists yet or a redesign was asked. A new eval covers layout options for one feature of an existing app, delivered as standalone files.
