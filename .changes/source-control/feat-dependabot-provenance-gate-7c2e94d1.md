---
bump: minor
---

### Security

- The pr-merge lane sends an otherwise auto-merged npm or pip Dependabot update to the review tier when its registry provenance changed since the newest earlier version that had one (`provenance-changed:<name>`), was dropped (`provenance-missing:<name>`), or cannot be read within 10 seconds and 20 registry reads (`provenance-unreadable:<name>`). The identity is the npm SLSA provenance's workflow repository and path (never the ref), else the npm trusted publisher with any `oidc:` prefix stripped, or the PyPI PEP 740 publisher. The `dependency --ci` review quotes each review-only `control` verbatim in `evidence`, which the verdict job now checks.
