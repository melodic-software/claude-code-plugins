---
bump: minor
---

### Added

- `comments --ci` answers the top-level pull request comments a person on the base's trusted-actor list addressed to the pr-unblock lane (a line starting `PR-fix lane:`). The review-thread tool's new `comments` action prints them as data, and `record <PRC_id>` takes the one disposition `answered`, which the reply job posts as one top-level comment. The mode makes no edit for a comment.
