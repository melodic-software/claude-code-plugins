---
bump: patch
---

### Changed

- The prototype page's pin helper, `shared/web/proto-pin.js`, is now a generated copy of the
  shared `lib/ui-feedback/proto-pin.js`. Its `pinned` message also carries a structural anchor
  that the prototype page ignores; the page behaves as before.
