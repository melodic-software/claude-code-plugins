---
bump: patch
---

### Changed

- pr-verify names a FAIL verdict's artifact with `-i` and the issues its verdict records, ascending and joined by dots (`write-verdict.mjs` `artifactName`), so the pr-merge gate counts it toward each issue's repeated-fail cap from the artifact listing alone. PASS and PASS-NOTES names are unchanged. The writer checks every name against the readers' pattern (`NAME`, now kept in `write-verdict.mjs` and re-exported by `resolve-pr.mjs`) and fails the job before upload on one no reader takes. The resolver reads the pull request's linked issues before it checks whether the head was judged, and looks up its own FAIL under the `-i` name too; a FAIL another pull request left at the same head is still missed and that head judged again, at the cost of a run.
