---
bump: patch
---

### Changed

- The work-items skills no longer stamp, read or gate on the `work-class:` labels
  (`read-only`, `mechanical`, `scoped`, `structural`). Triage applies the autonomous-eligible role
  label with no class label, and every session runs the issue trust test first: an item that fails
  it takes the human-gated role label, plus `provenance: untrusted` where the session may write it.
  The work-loop intake sweep's escalation proposes the role-label swap
  in place of a `Proposed work class:` line.
- The holds in triage, the work-loop drain and the attended queue read `provenance: untrusted` and
  `provenance: signal`. The legacy `work-class: untrusted-provenance` stays only where the
  frontier's human floor still holds it: the provenance-removal hold, the attended queue's flip and
  floor rules, and triage's human-gated sweep skip list and pairing ban.
- `/work-items:setup` checks and provisions `provenance: untrusted` alone (`check` probe 7 and
  `apply` step 3); it no longer checks or creates the four `work-class:` labels.
