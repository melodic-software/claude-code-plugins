---
bump: minor
---

### Added

- pr-merge's re-fire step (`refire-refused.mjs`) now also pushes an empty commit for a pr-unblock `address-feedback` run whose "Request the lane token" step failed transiently: `broker-unreachable`, or `lane-token-denied` with a 5xx status. No dispatcher tick retries that activity on the same head, so such a run stranded the pull request until a person re-fired it. The activities `pr-unblock-dispatch` already retries (resolve-conflicts, review-dependency, fix-ci) are left to it, and a token 403 is re-fired only for `workflow-modified`, as before. Each transient re-fire is recorded in a `<!-- pr-lane-refire transient run <id> tree <tree> head <head> -->` marker and capped at one per failed run and two per head tree, so a broker outage cannot chain empty commits on one change.
