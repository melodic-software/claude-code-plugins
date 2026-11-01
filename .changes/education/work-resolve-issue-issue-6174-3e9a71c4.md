---
bump: minor
---

### Added

- `/education:illustrate` pages take the explainer's title as their `<title>`, so a published explainer is named for its subject, not "Explainer".
- The bundled view builder (`lib/view-builder.mjs`) takes an optional `title` and writes it into the page's `<title>` as escaped plain text, with whitespace collapsed and the text cut to 80 characters (rendered-views rule 5).
