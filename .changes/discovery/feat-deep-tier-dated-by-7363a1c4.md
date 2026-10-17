---
bump: minor
---

### Added

- The `/discovery:research` deep tier carries `dated_by:` through the sweep. A reader of a living page that prints no date derives a date by the family method (`sitemap-lastmod`, `ms-date` or `source-commit`) and may request the sitemap at its page's origin to do it; the method reaches the findings' sources, and `deep-tier.md` step 5 copies it into the artifact. A `dated_by:` naming a serve-time header is dropped and the source stays `undated`.
