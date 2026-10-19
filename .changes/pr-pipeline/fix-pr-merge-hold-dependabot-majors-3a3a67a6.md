---
bump: minor
---

### Added

- `merge.dependabot.majors` (`hold` or `review`, default `hold`) decides a Dependabot pull request
  with a major update, or with an update whose version cannot be read (a SHA pin), marked
  `<name>(unreadable)`, or whose title and commit metadata disagree, marked `<name>(disagree)`.
  Under `hold` the pr-merge lane refuses it with the reason `dependabot-major-held:<names>`
  whatever the review verdict says, and escalates it once: a marked comment whose first line is the
  `<!-- work-items:escalation lane=pr-merge kind=escalated -->` marker, so
  `/work-items:attend-queue` lists it, then the tracker's human-gated role label. `review` keeps the
  earlier behavior, where the lanes App's `verdict=merge` marker merges it. This repository sets
  `hold`. Non-major tiers and the publisher rule are unchanged. `version` stays 2.
