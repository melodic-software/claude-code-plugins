---
bump: patch
---

### Changed

- A trusted person's approving review of a head that changes a hold path or widens the trusted-actor list carries over a later merge of the base when the merge changes nothing of its own, so the merge no longer sends the pull request back to them. Only an approving review lifts these holds: removing the human-gated label does not, and a dismissed approval never counts. The approval carries only when every commit since is a merge of commits the base branch holds and the whole net change against the base's tip commit is the same at both heads; the base is read once by its full ref. The owner's cost decision carries by the same rule. A carried approval does not lift the verifier, issue-link or pr-verify FAIL holds.
