---
bump: minor
---

### Added

- pr-merge's `enable-auto-merge` arms a trusted author's pull request (an id on the trusted-actor list, not the lanes App or a dependency manager) at the head pr-verify passed, with the lanes App token and `expectedHeadOid` that head, when it is not a draft, armed, queued or a stack layer, carries no hold label (`do-not-merge`, `pr-verify-failed`, `security: outside-actor`, `needs-human` or the human-gated label), has no `Hold:` or "do not merge" body line, changes no lane source pr-review-main reviews, and the verdict reader counts a PASS or PASS-NOTES at the head. A lane-source pull request is left to a person: no reader decides whether pr-review-main's findings are settled. Scheduled and hand-started runs arm it; the pr-verify wake still serves lanes App pull requests only.
