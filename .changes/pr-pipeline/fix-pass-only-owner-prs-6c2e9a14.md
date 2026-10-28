---
bump: patch
---

### Fixed

- A pr-verify pass now clears the fail-note threads from earlier heads on a PR a human on the trusted-actor list opened, not only on a lanes App PR. `verify-notes.mjs` posts fail notes on such an adopted PR, but `feedback-dispatch.mjs` skipped the pass-only round there (`#<n> was not opened by the lanes App`), so the threads stayed open and required thread resolution blocked a passing PR. The pass-only round alone takes that author; every other address-feedback round still goes only to lanes App PRs.
