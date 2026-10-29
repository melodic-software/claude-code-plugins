---
bump: patch
---

### Fixed

- The cost decision's push-history check reads the head branch's whole activity, not one page
  of 100. The activity API keeps a branch name's history across deletions, so a branch recreated
  for each sync filled the page for good, and the full-page refusal held its pull request with no
  way to clear. pr-merge (`merge-holds.mjs`), the babysit merge policy and ci-status's cost-hold
  step follow the Link header's `rel="next"` cursor until a page of fewer than 100 entries. The
  hold stays on a read that fails on any page, an empty or non-list page, a full page with no
  next link, more than 20 pages (2000 entries; the busiest reused name had 564) or, in pr-merge,
  a next link with no new cursor.
