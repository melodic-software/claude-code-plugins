---
bump: patch
---

### Fixed

- Native auto-merge: a lanes App pull request whose head moved after its arm no longer merges at a head the arming checks never judged. GitHub turns auto-merge off only on a push by someone without write access, so the merge queue's `ci-status` now holds a head the lanes App's newest pin does not name (`merge-holds.mjs` `pinHold`), unless a trusted person's approval of that head lifts it. `enable-auto-merge` also disarms an armed pull request whose head that pin does not name, and pins and arms the new head once its next scheduled run judges it.
