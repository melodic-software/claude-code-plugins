---
bump: patch
---

### Fixed

- The unattended merge gate takes a pull request's head pushers from the head branch's repository
  activity, not only from commit author and committer logins, which GitHub links through an email
  the pusher chooses. A collaborator who pushes a commit carrying the agent identity's email is now
  excluded from counting as an independent resolver of the lane's review threads. A push history
  whose newest move did not bring the head, a move with no actor, or a commits list that does not
  hold the pinned head refuses the candidate with `head-pusher-unproven`.
