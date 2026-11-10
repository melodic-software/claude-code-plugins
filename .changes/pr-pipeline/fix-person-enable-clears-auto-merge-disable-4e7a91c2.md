---
bump: patch
---

### Fixed

- pr-merge's auto-merge sweep no longer holds a pull request forever on a person's old auto-merge disable: it reads the newest of the auto-merge-disabled, auto-merge-enabled and added-to-merge-queue events in the same query, and holds only while that newest event is a disable by a user account, so a person's later enable or merge-queue add clears it
