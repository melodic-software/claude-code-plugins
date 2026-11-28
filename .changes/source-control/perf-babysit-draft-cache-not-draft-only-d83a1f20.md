---
bump: patch
---

### Changed

- babysit-prs: the run cache shares only a "not a draft" judgment of a FAIL between one pr-merge run's gate processes; a judgment that the FAIL came from a draft run, which dismisses it, is read fresh by each process and never stored or served, so a stored answer can keep a FAIL counted but never dismiss one.
