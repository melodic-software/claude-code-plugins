---
bump: patch
---

### Changed

- `shared/web/proto-pin.js`, the generated copy of `lib/ui-feedback/proto-pin.js`, adds control
  values to its view snapshot and answers the notes host's Controls tab, both only on a page that
  carries the controls runtime. The prototype page loads no controls runtime and ignores the
  ready message's new fields and the new content message, so it behaves as before.
