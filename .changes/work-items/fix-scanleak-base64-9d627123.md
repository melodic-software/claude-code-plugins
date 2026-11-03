---
bump: patch
---

### Fixed

- The lane telemetry body gate's leak scan (`scanLeak` in the shared `lib/publish-gate.mjs` copy) now also decodes base64 and base64url runs, up to two layers and including runs of non-ASCII UTF-8 text, and refuses a body with a GitHub token or Anthropic key inside one (#8295).
