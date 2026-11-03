---
bump: patch
---

### Fixed

- The shared `lib/publish-gate.mjs` copy's leak scan (`scanLeak`) now also reads JSON-encoded text with its `\n`, `\r` and `\t` escapes decoded, so a credential at the start of a line or after a tab blocks. Nothing in this plugin calls `scanLeak`, and its publish gate behaves as before (#12562).
