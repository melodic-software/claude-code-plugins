---
bump: patch
---

### Fixed

- Seven skill descriptions (`/docs-hygiene:write-for-agents`, `write-for-humans`, `audit-encapsulation`, `audit-progressive-disclosure`, `extract-ssot`, `audit-derivability`, `audit-noise`) now say to load the skill even when the request looks small or names the job in plain words, so the skill fires on the requests its eval cases make.
- `/docs-hygiene:write-for-humans` adds a finished-draft check that each term's gloss sits right after its first use, in the same sentence.
- `/docs-hygiene:rename-references` states that a small tree or a bare-token search excuses no form of the pattern library.
- The `control-self-explaining-error-cut` eval case is tagged `contrast`, not `control`: it requires the skill call, which the validity gate skips for `control` cases.
