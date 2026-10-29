---
bump: minor
---

### Added

- `address-feedback` also serves an adopted owner PR: one a `kind: human` account on the base's trusted-actors list opened, under an `adoption` section, with no `Hold:` body line, once the PR and its head commit are `adoption.idle-hours` old, the rule fix-ci adopts by. Its replies post as the lanes App, so the owner's babysit worker tier can tell a lane answer from the person's and resolve the outdated threads the lane answered ([#10763](https://github.com/melodic-software/claude-code-plugins/issues/10763)). The half-hourly sweep sends one such idle PR per tick whose reviewed head has no round yet, since its review usually finishes while the session is still active. Lanes App PRs, and every other author's PRs, are dispatched as before.
- On an owner PR, `publish-feedback` posts each answer and leaves the thread open, since the lanes App cannot resolve a thread on a PR it did not open, and the select job skips a thread the person wrote or answered with no stop instead of escalating `feedback-untaken-threads`.
