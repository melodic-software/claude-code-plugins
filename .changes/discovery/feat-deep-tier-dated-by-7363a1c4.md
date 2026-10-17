---
bump: minor
---

### Added

- The `/discovery:research` deep tier carries `dated_by:` through the sweep. A reader of a living page that prints no date derives a date by the family method (`sitemap-lastmod` or `ms-date`) and may request a `sitemap.xml` at its page's origin or one of its parent paths to do it, so a code.claude.com `/docs/en/` page reaches `https://code.claude.com/docs/sitemap.xml`; the method reaches the findings' sources, and `deep-tier.md` step 5 copies it into the artifact. A `dated_by:` naming a serve-time header is dropped and the source stays `undated`.
