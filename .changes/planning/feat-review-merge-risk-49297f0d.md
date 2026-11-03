---
bump: patch
---

### Changed

- `/planning:design` reads the one-way and two-way door definition from a shared reference that `/review:merge-risk` also reads. The definition widened: a decision whose effect has already left the code (data rewritten or deleted, a message sent, a package published, a third-party call with a lasting effect) is now a one-way door and gets the ADR prompt, where before only a decision others build on was.
