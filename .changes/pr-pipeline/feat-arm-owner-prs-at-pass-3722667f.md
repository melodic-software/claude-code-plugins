---
bump: minor
---

### Added

- pr-merge's `enable-auto-merge` arms a trusted author's pull request (an id on the trusted-actor list, not the lanes App or a dependency manager) at the head pr-verify passed, with the lanes App token and `expectedHeadOid` that head, when it is not a draft, armed, queued or a stack layer, carries no hold label (`do-not-merge`, `pr-verify-failed`, `security: outside-actor`, `needs-human` or the human-gated label), has no `Hold:` or "do not merge" body line, changes no lane source pr-review-main reviews, and the verdict reader counts a PASS or PASS-NOTES at the head. The arm skips every lane-source pull request until a reader decides whether pr-review-main's findings at a head are settled. It posts the lanes App's pin at the head before arming, and the next scheduled run disarms one whose newest pin names another head. Scheduled and hand-started runs arm it; the pr-verify wake still serves lanes App pull requests only, since the token broker mints it for no other author.
- `ci-status` in the merge queue holds a judged non-lanes author's pull request whose newest lanes App pin names another head, was edited, or whose edit time does not read (`merge-holds.mjs` `pinHold`), so a trusted pull request armed at a passing head and pushed again does not merge the unjudged head; a trusted approval of the live head lifts it.
