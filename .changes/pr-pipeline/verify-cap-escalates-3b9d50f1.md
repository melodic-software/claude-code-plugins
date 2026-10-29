---
bump: patch
---

### Fixed

- A pull request at `merge.max-verify-fails` (`verify:repeated-fail`) or too old to judge
  (`verify:too-old`) no longer sits unarmed with no signal. Both stay permanent for the head, and
  the pr-merge lane escalates them to a person: the gate, or `enable-auto-merge.mjs` on a lanes App
  pull request, adds the human-gated label once and posts one escalation comment per head naming
  the refusal, the FAILed heads and what the person does. That comment no longer says the lanes
  clear the reason on their own.
- `pr-feedback-dispatch.yml` and `pr-unblock-dispatch.yml` start no address-feedback or fix-ci
  round, and post nothing, on a pull request the gate's reader refuses `verify:repeated-fail`
  (`.github/scripts/pr-unblock/verify-cap.mjs`, with each dispatcher job's existing read token).
