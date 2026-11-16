---
bump: patch
---

### Fixed

- The babysit merge gate's verdict reader clears an earlier pr-verify FAIL whose every note starts with `PR body` once a trusted person edits the pull request body after that FAIL and a counted pass at a head of the same change follows the edit, so a body-only FAIL no longer refuses `verify:earlier-fail` on a head that only merged the base. A FAIL with any other note keeps the same-change rule.
