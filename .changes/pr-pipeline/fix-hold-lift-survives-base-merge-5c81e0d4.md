---
bump: patch
---

### Changed

- A trusted person's approving review of a head that changes a hold path or widens the trusted-actor list carries over a later merge of the base, so the merge no longer sends the pull request back to them. Only an approving review lifts these holds: removing the human-gated label does not, and a dismissed approval never counts. The approval carries only when every commit since is a merge of commits the base branch holds, no hold path changes beyond the approved head, and no other file does unless the base changed it. The owner's cost decision carries by the same rule, on the whole net change. A carried approval does not lift the verifier, issue-link or pr-verify FAIL holds.
