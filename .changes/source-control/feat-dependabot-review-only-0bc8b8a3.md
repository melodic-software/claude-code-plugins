---
bump: minor
---

### Security

- The pr-merge lane sends every Dependabot update to a dependency the standards Dependabot policy lists under `autoMerge.reviewOnly` to the review tier (`review-only:<dependency>`), whatever its version change, and every Dependabot pull request to review (`dependabot-policy-unreadable`) when `.github/standards/dependabot-policy/policy.json` does not read at the base. The `dependency --ci` review requires a `merge` verdict on such a pull request to cite the entry's `control` and state what it checked.
