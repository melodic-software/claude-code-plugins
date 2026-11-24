---
bump: patch
---

### Fixed

- `/multi-agent:route vendors` counts a board record that names a model without the effort
  suffix the vendor's current ids carry (a base name such as `gemini-4-neon` for
  `gemini-4-neon-high`), canonicalized to `<model>-<record effort>` when that id exists, else to
  the first such id the vendor lists; it no longer abstains for that vendor. A version or other
  non-effort suffix still abstains.
- Route's board fetch (`fetch-boards`) passes each registry row's `expect` marker and
  `--render-fallback`, so a blocked or script-drawn board page renders through the Firecrawl CLI
  when the docs-cache `renderer` is `firecrawl`, and a page without its marker is unread.
