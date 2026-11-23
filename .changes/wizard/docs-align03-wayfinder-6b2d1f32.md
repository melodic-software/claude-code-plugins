---
bump: patch
---

### Changed

- Before a configuration stage that a person would click through in a vendor dashboard, `/wizard:generate` checks the vendor's docs for a management API or CLI; when one exists, the wizard keeps only the token stage and the agent does the configuration afterwards as code.
