---
bump: patch
---

### Fixed

- pr-verify's repeated-fail cap (`merge.max-verify-fails`, `verify:repeated-fail`) closes a pull request only when its current head itself has a FAIL that is not superseded (owner decision Q245, [#17646](https://github.com/melodic-software/claude-code-plugins/issues/17646)). FAILs at superseded heads no longer close it: a pass at the head goes on to the normal pass decision. pr-merge's `capped_close` and pr-unblock's `verify-cap.mjs` read the same reader, so both follow it; the README's Verifier verdict section, the schema and `pr-pipeline.yaml` say so. pr-unblock's address-feedback and fix-ci dispatchers no longer record a capped head as handled, so a head whose FAIL a later pass supersedes is dispatched again; the dispatch record's version is 7, so heads an earlier version recorded at the cap are read again.
