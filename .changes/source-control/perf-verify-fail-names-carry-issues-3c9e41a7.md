---
bump: patch
---

### Changed

- The pr-merge gate's verdict reader (`babysit_verify_evidence`) accepts a pr-verify artifact name that ends with `-i` and the dot-joined numbers of the issues its verdict records (at most 10). The cross-pull-request repeated-fail cap counts every counted FAIL whose name carries one of the pull request's closing issues, read from the artifact listing the gate already holds, so it adds no request. A name without the issues keeps today's rule. pr-verify does not write these names yet.
