---
bump: patch
---

### Fixed

- `/user-interface:design` now auto-invokes on plain requests to build a component or page, or to choose between building one and adopting a library. `/user-interface:write-css` keeps requests for the styling alone, and each description names the other as its neighbor. Invocation probes for both skills are in `probes/design.json` and `probes/write-css.json`.
