---
bump: patch
---

### Fixed

- pr-merge's `clear-escalations` sweep removes `needs-session`, with no comment, once a same-head
  retry cleared the lane stop that added it: the lanes App added the label last, and each stop
  routed to it since then has a `success` status newer than the stop on that stop's head. A person's
  label, a stop whose failure still stands, or an unread status keeps it. The sweep reads at most
  five pull requests a run, from a rotating offset. The `merge` job gains `statuses: read` for this.
