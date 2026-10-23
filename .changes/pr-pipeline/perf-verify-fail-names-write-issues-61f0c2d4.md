---
bump: patch
---

### Changed

- pr-verify names a FAIL verdict's artifact with `-i` and the issues its verdict records, ascending and joined by dots (`write-verdict.mjs` `artifactName`), so the pr-merge gate counts it toward each issue's repeated-fail cap from the artifact listing alone. PASS and PASS-NOTES names are unchanged.
