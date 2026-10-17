---
bump: minor
---

### Security

- The pr-merge lane sends every Dependabot update to a dependency the standards Dependabot policy lists under `autoMerge.reviewOnly` to the review tier (`review-only:<dependency>`), whatever its version change, and every Dependabot pull request to review (`dependabot-policy-unreadable`) when `.github/standards/dependabot-policy/policy.json` does not read at the base. An entry's `directory` covers a changed path in it, and a `github-actions` entry also covers the workflow and action files the content rule gives that directory (`/` covers `.github/workflows/` and `.github/actions/`).
- The pr-merge lane sends an otherwise auto-merged npm or pip Dependabot update to the review tier when its registry provenance changed since the newest earlier version that had one (`provenance-changed:<name>`), was dropped (`provenance-missing:<name>`), or cannot be read within 10 seconds and 20 registry reads (`provenance-unreadable:<name>`). The identity is the npm SLSA provenance's workflow repository and path (never the ref), else the npm trusted publisher with any `oidc:` prefix stripped, or the PyPI PEP 740 publisher.
- The `dependency --ci` review requires a `merge` verdict on a review-only dependency to quote each matched entry's `control` verbatim in `evidence` and state what it checked; the verdict job checks the quote by script and escalates a merge that lacks one.
