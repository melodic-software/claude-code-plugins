---
bump: patch
---

### Fixed

- pr-verify judges a lanes App pull request whose `ci-status` fails only on a hold an approving review of the head lifts (a hold path, a trusted-actor list widening), so the person approves a head pr-verify has already judged. `ci-status` still fails until that approval, and any other failure still keeps pr-verify from judging the head.
