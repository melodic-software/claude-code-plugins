---
bump: patch
---

### Changed

- pr-verify names a FAIL verdict's artifact with `-i` and the issues its verdict records, ascending and joined by dots (`write-verdict.mjs` `artifactName`), so the pr-merge gate counts it toward each issue's repeated-fail cap from the artifact listing alone. PASS and PASS-NOTES names are unchanged. The writer checks every name against the readers' pattern (`NAME`, now kept in `write-verdict.mjs` and re-exported by `resolve-pr.mjs`) and fails the job before upload on one no reader takes. The resolver checks the names without issues first and skips a head judged under one without reading the linked issues; only then does it read them, which the spec needs anyway, and look up its own FAIL under the `-i` name; a FAIL another pull request left at the same head is still missed and that head judged again, at the cost of a run, and so is this pull request's own FAIL once a body edit changes its linked issues at the same head, one run per change of the issue set; neither changes the gate's decision, since the earlier FAIL stays tied and refuses the head. A FAIL whose issues no name carries (more than 10, or a number over 10 digits) keeps the plain name with a warning, and the resolver never looks such a name up, so that pull request is still judged.
