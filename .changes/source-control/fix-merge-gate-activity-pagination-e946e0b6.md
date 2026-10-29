---
bump: patch
---

### Fixed

- The cost decision's push-history check reads the head branch's whole activity, not one page
  of 100. The activity API keeps a branch name's history across deletions, so a branch recreated
  for each sync filled the page for good, and the full-page refusal held its pull request with no
  way to clear. pr-merge (`merge-holds.mjs`), the babysit merge policy and ci-status's cost-hold
  step follow the API's `after` cursor to the end. A read that fails on any page or a page that
  is no list still keeps the hold, and so, in pr-merge and the babysit policy, does a next link
  with no new cursor or more than 50 pages.
