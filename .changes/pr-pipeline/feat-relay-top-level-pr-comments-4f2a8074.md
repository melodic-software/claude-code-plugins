---
bump: minor
---

### Added

- The pr-unblock lane answers a top-level comment on a lanes App pull request when a person on the trusted-actor list wrote it with a line starting `PR-fix lane:` and the lanes App has not answered it. `pr-dispatch-feedback.yml`'s half-hourly sweep sends such a head after its fix requests, under the same bounds, and a review completion dispatches a head with one even with no unresolved thread. `address-feedback-select` lists up to ten in `threads.json`'s `pr_comments`, as data, and `publish-feedback` posts one top-level answer per comment, first line `<!-- pr-unblock:answered-comment <id> -->`. A round that answered only comments posts no round marker. No workflow trigger, token, permission or trusted-actor source changes.
