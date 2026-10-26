---
bump: patch
---

### Fixed

- Under `merge.lane-prs: native`, `clear-escalations.mjs` judges `enable-auto-merge`'s person refusal again at the head it was raised at, but only when its recorded verifier or risk cause is one the lanes clear (every code on `LANE_CAUSES`, a label set before its cause became a lane's): the gate's reader runs, and the label comes off as `refusal-cleared` when nothing refuses, or only lane causes refuse, read at least as far as the recorded one. A recorded cause a person clears (an issue link, a security finding, a trust-gate widening, a cost hold, a high path, an untrusted spec, the repeated-fail cap, an unknown code) is never read and never lifted at its head (owner decision Q-CLEAR B); a person removes the label, or the `head-moved` clear does once the head moves. At most three reader runs a run, rotated with the run number.
- `pr-merge.yml`'s merge job allows 45 minutes, up from 30, and the escalation clear step 15, up from 3, so the clear's reader runs fit beside the gate's own budget.
