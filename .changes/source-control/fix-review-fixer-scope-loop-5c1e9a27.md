---
bump: minor
---

### Changed

- `comments --ci` answers a code-review advisory whose change falls outside the closing issue's acceptance criteria or Out of scope list with the new `follow-up` disposition instead of a fix; the review-thread tool's new `issues` command prints the closing issues' text, and `record` takes `follow-up` only on a thread the select job marked `may_follow_up`
