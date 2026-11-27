---
bump: patch
---

### Fixed

- Exclude validated `<style>` bodies without raw `<` from the HTML text escaping scan in shared `html-escape.mjs` and `view-builder.mjs` so quoted CSS font stacks, attribute selectors and child combinators pass validation.
