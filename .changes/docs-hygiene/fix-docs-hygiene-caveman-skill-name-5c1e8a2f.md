---
bump: patch
---

### Fixed

- `/docs-hygiene:compress` now calls caveman's compress skill by its real name, `caveman:caveman-compress`. The old name, `caveman:compress`, matches no skill or command in caveman 4.0.1, so with `compress_articles: cut` the caveman backend could not be invoked.
