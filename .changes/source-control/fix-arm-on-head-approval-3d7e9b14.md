---
bump: patch
---

### Fixed

- The pr-merge lane's risk score (`babysit_verify_evidence.py evidence --lane-reviews`) drops a configured or floor high path (`high-path:<glob>`) once a person on the trusted-actor list approved the pull request's current head, by the same rule `ci-status` lifts the hold path with (`babysit_merge_policy.path_lifters`, held equal to `merge-holds.mjs` `pathLifters`). An approval of an older head, an untrusted approver, a newer request for changes or a dismissal lifts nothing, and so does a review list or trusted-actor list that does not read. An aliasing path, symlink, submodule or mode change, and every cost, trust-gate, manifest, file-cap and review-lane hold, still hold.
