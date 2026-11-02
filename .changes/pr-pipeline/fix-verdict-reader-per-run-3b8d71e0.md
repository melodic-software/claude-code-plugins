---
bump: patch
---

### Fixed

- In the merge queue, ci-status titles every verifier hold's error annotation `pr-verify hold` (merge-holds.mjs `VERIFIER_TITLE`), so a `verify:unreadable` refusal no longer reads as a body hold of the step it shares. The verdict reader's short incremental artifact listing is read again after a wait before it pages every artifact, and the cold-read headroom counts the near-expiry caps once for the incremental reads and once for the whole listings' top-ups (1,681 to 1,739 at 7,522 artifacts).
