---
bump: patch
---

### Fixed

- The shared `lib/publish-gate.mjs` copy's leak scan (`scanLeak`) now also decodes base64 and base64url runs, up to two layers and including runs of non-ASCII UTF-8 text, and blocks a GitHub token or Anthropic key inside one. Nothing in this plugin calls `scanLeak`, and its publish gate behaves as before (#8295).
