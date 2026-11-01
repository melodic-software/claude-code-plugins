---
bump: minor
---

### Added

- The bundled view builder (`lib/view-builder.mjs`) takes an optional `title` and writes it into the page's `<title>` as escaped plain text, with whitespace collapsed and the text cut to 80 characters (rendered-views rule 5). Pages built without one keep their template's title.
