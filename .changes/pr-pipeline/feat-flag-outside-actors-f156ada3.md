---
bump: minor
---

### Added

- `security-outside-actor.yml` flags an issue or pull request when someone outside the
  organization opens or edits it, comments, or reviews on it: it adds `security: outside-actor` and
  `needs-human` and posts one comment per outside actor naming the login, without a mention, and the
  event, quoting none of their text. Members, owners and Bot senders start no job; everyone else is
  trusted only by numeric id on the default branch's trusted-actor list, and an unreadable list
  flags. No model, secret or kill switch; the job token holds `contents: read`, `issues: write` and
  `pull-requests: write`.
- `security: outside-actor` is a hold of its own, defined in `merge-holds.mjs`: the merge queue,
  auto-merge arming, intake triage, the work-unblock sweep and each activity whose
  `labels-absent` lists `needs-human` skip it, and only a person removes it. A Bot's push to a fork pull request is
  checked too.
