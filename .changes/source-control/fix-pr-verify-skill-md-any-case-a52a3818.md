---
bump: patch
---

babysit-prs: the merge gate's vendored-copy sync check treats a skill file named `SKILL.md` in any case as a `SKILL.md`, so a lowercase `skill.md` a sync adds or changes no longer keeps the drift issue's spec.
