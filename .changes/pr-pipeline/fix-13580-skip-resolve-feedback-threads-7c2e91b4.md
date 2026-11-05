---
bump: patch
---

### Fixed

- `resolve-feedback-threads` starts no job and asks the lanes token broker for no token on a PR no listed person opened (address-feedback-select's new `person-opened` output, the `ownerPull` test `resolve-threads.mjs` applies) or on a round whose upstream is a review-comment relay (the new `upstream-relay` dispatch input `feedback-dispatch.mjs` sends), where it has no thread to resolve; a person's PR on a review-completion round runs it as before
