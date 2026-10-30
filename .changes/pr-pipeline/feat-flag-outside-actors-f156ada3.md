---
bump: minor
---

### Added

- `security-outside-actor.yml` flags an issue or pull request when someone outside the
  organization opens or edits it, comments, or reviews on it: it adds `security: outside-actor` and
  `needs-human` and posts one comment per outside actor naming the login, without a mention, and the
  event, quoting none of their text. Members, owners and Bot senders start no job, except a Bot on a
  fork pull request, which is checked on any action; everyone else is trusted only by numeric id on
  the default branch's trusted-actor list, and an unreadable list flags. The labels are written on
  every flagged event, whatever the payload shows. No model, secret or kill switch; the job token holds `contents: read`, `issues: write` and
  `pull-requests: write`.
- `security: outside-actor` is a hold of its own, defined in `merge-holds.mjs`: the merge queue,
  auto-merge arming, intake triage, the work-unblock sweep, ci-status on a pull request and
  every pull request activity (including the write runner) skip it. Only a person on the
  trusted-actor list removes it: any other removal, a Bot's or a member's not on the list included,
  puts it and `needs-human` back and posts one comment naming the remover without a mention.
