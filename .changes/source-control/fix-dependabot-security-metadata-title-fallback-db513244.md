---
bump: patch
---

### Fixed

- The Dependabot classifier (`babysit_dependabot.py`) now reads a security update's version jump from its own verified commit subject when the commit metadata names the package and version but carries no `update-type`, so a patch such as `fast-uri` 3.1.8 to 3.1.9 is no longer held as an unreadable version. The subject must open with `Bump <name> from <a> to <b>` for the same package and version; the editable PR title is never read for it, and a group subject, a missing metadata version or an unreadable subject version still holds.
