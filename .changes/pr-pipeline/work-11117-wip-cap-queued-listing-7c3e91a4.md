---
bump: patch
---

### Fixed

- check-wip-cap reads the queued `agent-ready` issues from the repository issues listing
  (`GET /repos/{repo}/issues`, open, oldest first) in place of the search API, whose results carry
  no recency guarantee, so parallel apply-verdict admissions count against a fresh queued count.
  Pull requests and the hold labels (`needs-human`, `needs-owner-decision`,
  `status: needs-decision`, `status: needs-info`, in any case) are left out client-side. A failed
  page, or one that is not a list, leaves the queued count unread (`admission_basis`
  `fail-open`), so intake admission admits nothing, as before. Past 10 pages one more issue
  counts as unlisted and admissions pause. The pull request searches are unchanged.
- Intake admission reads the racing admissions' `admission-deferred` listing before the
  `agent-ready` one. A run that adds `agent-ready` and then drops its claim between the two
  reads was missing from both, so a parallel admission could take one place past the room.
  The claim order is unchanged.
- Intake admission tests run `Promise.all` bursts of 2, 4 and 5 concurrent `admit()` runs
  against one shared fake GitHub with room 1, 2 and 3: no burst admits past its room, every
  shuffled burst admits, and a burst whose runs all read the room before any claim admits
  exactly the room.
