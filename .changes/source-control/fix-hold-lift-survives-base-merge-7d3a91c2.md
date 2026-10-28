---
bump: patch
---

### Fixed

- A trusted person's approving review of a head that changes a hold path now survives a later merge of the base, so a base merge no longer sends a lanes App pull request back to its owner. Each trusted person's newest review that approves, requests changes or was dismissed counts, and lifts only when it approves; a dismissed approval never counts, and removing the human-gated label lifts no hold path. The approval carries to the current head only when every commit since is a merge whose other parents the base branch holds, each hold-path file the current head changes against the base is changed identically at the approved head, and the current head changes no file the approved head did not unless the base changed it (`base_merge_carry`, `base_facts`, `carried_lifters`, and `merge-holds.mjs` `baseMergeCarry`, `baseFacts` and `liftersOf`). A non-merge commit, a merge of another branch or of a commit the base does not hold, a force push that rewrites the approved head, a merge that edits or adds a hold path or edits any other file, an untrusted approver, a head in a fork, and any unreadable input carry nothing. A carried approval lifts only the hold path; it never lifts the verifier hold.
- The owner's cost decision carries to a later head only when every commit since is a merge whose other parents the base branch holds (`base_merges_only`), as well as the same net change. A rebase, or a commit of its own that leaves the net change the same, no longer carries it.
