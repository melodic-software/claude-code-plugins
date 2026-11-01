---
bump: patch
---

### Fixed

- A pr-verify pass that supersedes a FAIL at the same head now resolves that FAIL's fail-note threads on a lanes App pull request. Before, a pass-only round resolved only fail-note threads from an earlier head, so after a trusted body edit or relink let a pass at the same head supersede the FAIL in the merge gate, the FAIL's own threads stayed open and held the merge. `post-verify-notes` now starts the pass-only round for any open fail-note thread. The dispatch job reads the merge gate's own judgment, `babysit_verify_evidence.py` `supersededAtHead`, in the FAIL-cap read it already makes, and sends the new `pr-unblock.yml` input `verify-superseded-head` only when that read at the head says the FAIL there was superseded. `address-feedback-select` then also lists the same-head threads and names the head in `run.json`'s `superseded_head`, and `publish-feedback` resolves them only under that name. A failed or unreadable read, an older reader without the field, or a FAIL not superseded keeps the threads open. Because those threads can now be resolved, `post-verify-notes` no longer counts a note in a resolved thread as already posted: a later FAIL at the same head posts its notes again, so its round has an open thread to work.
