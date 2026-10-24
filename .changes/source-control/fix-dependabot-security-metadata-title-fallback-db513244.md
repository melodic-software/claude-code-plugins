---
bump: patch
---

### Fixed

- The Dependabot classifier (`babysit_dependabot.py`) now reads a security update's version jump from its single-package title when the commit metadata names the package and version but carries no `update-type`, so a patch such as `fast-uri` 3.1.8 to 3.1.9 is no longer held as an unreadable version. The title must name the same package and the same new version; a group title or an unreadable title version still holds.
