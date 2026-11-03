---
bump: minor
---

### Added

- pr-unblock's `resolve-feedback-threads` activity resolves review threads on a pull request a
  person on the trusted-actors list opened, where `publish-feedback`'s `publish-artifact` token is
  no writer and leaves its answers open. It resolves a thread whose comments are all a review
  bot's or the lanes App's, whose finding no reviewer comment rates CRITICAL and an adjudicator
  could judge, and that the lane answered (its VALID reply or a `finding-answered` adjudication is
  the last comment) or GitHub reports outdated with no lane reply that left it open. A CRITICAL
  finding, a person-decided security finding and any thread a person wrote or joined stay open.
  It runs in its own job after `publish-feedback`: a script with no model, granted
  `mutate-branch` (`contents: write`), reading the threads from GitHub itself
  (`resolve-threads.mjs`, now on the hold floor as an enforcement path), and judging each thread
  again on its re-read comments, edits included, before resolving it. It also runs after
  `publish-feedback`'s own stops (an escalation, `finding-stands`, `no-model-turn`), never after
  a kill-switch or gate skip. `publish-feedback`'s job and grant do not change.
- A script leaf's `checkout: base` has the write runner skip the PR head checkout and its SHA
  assert, so the job holding the lane token holds only the trusted base checkout, credentials not
  persisted. resolve-config outputs `checkout` (`head` by default) for every script activity.
