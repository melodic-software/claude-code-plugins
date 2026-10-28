---
bump: patch
---

### Fixed

- A trusted person's lift of a hold path now survives a later merge of the base, so a base merge no longer sends a lanes App pull request back to its owner. The lift is an approving review of a head, or the person's own removal of the human-gated label while that head was the branch's head (bound by the branch's push history; a push within 60 seconds before the removal binds nothing). It carries to the current head only when every commit since is a merge and each hold-path file the current head changes against the base is changed identically at the lifted head (`base_merge_carry`, `carried_lifters`, and `merge-holds.mjs` `baseMergeCarry` and `liftersOf`). A non-merge commit, a merge of another branch, a force push that rewrites the lifted head, a merge that edits or adds a hold path, a dismissed or withdrawn approval, a removal by an untrusted account or through an App, and any unreadable input carry nothing. A carried lift does not lift the verifier hold.
- The owner's cost decision carries to a later head only when every commit since is a merge (`base_merges_only`), as well as the same net change. A rebase, or a commit of its own that leaves the net change the same, no longer carries it.
