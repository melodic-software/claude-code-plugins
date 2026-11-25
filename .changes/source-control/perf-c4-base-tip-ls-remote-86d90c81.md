---
bump: patch
---

### Changed

- The babysit merge policy reads a branch tip (`base_tip`) with one unauthenticated
  `git ls-remote https://github.com/<owner>/<name> refs/heads/<base> refs/tags/<base>` first, so
  the read spends no REST quota. It takes the SHA only when the listing names `refs/heads/<base>`
  once as 40 hex and holds no tag of the same name, the rule the CI workflows' main's-tip listing
  uses. Anything else (a failed or timed-out listing, no `git`, a private repository, a
  tag named like the branch, or `GH_HOST` naming a host other than github.com) reads
  `git/ref/heads/<base>` over REST as before, and an unreadable tip still fails closed. The read
  happens at the same moment as before, so the default-branch config, the trusted-actor list and
  the standards repository's tip are judged at a tip as fresh as the REST read gave.
