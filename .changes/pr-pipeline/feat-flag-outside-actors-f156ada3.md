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
