---
bump: patch
---

### Changed

- A trusted person's lift of a hold path or a trusted-actor list widening carries over a later merge of the base, so the merge no longer sends the pull request back to them. The lift can be an approving review (including one GitHub dismissed as stale on a push) or the person's own removal of the human-gated label while that head was the head. It carries only when every commit since is a merge and no hold path changes beyond the lifted head. The owner's cost decision carries by the same rule, on the whole net change. A carried lift does not lift the verifier hold.
