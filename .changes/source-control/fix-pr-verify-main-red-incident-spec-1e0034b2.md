---
bump: patch
---

### Fixed

- The babysit merge gate counts a pr-verify pass whose linked issue is a main-red incident the
  monitoring lane filed (github-actions[bot] wrote it and nobody else last edited it, under that
  lane's title and `incident:main-red` marker line) as a trusted spec, as pr-verify does, instead
  of refusing it `verify:untrusted-spec`.
