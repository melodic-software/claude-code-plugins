---
bump: patch
---

### Changed

- babysit-prs: the gate processes of one pr-merge run share a draft-run judgment of a FAIL (the checks-run listing, verifier run and jobs reads) through the run cache, so only the first process reads them; an answer cut short by a failed read is not shared.
