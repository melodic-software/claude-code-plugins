---
bump: minor
---

### Added

- `/review:explain-change` digest pages take the digest's title as their `<title>`, so a published digest is named for its change, not "Change Digest".
- The bundled view builder (`lib/view-builder.mjs`) takes an optional `title` and writes it into the page's `<title>` as escaped plain text, with whitespace collapsed and the text cut to 80 characters (rendered-views rule 5).
