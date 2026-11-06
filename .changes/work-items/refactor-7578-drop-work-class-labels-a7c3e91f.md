---
bump: patch
---

### Changed

- The work-items skills no longer stamp, read or gate on the `work-class:` labels
  (`read-only`, `mechanical`, `scoped`, `structural`). Triage applies the autonomous-eligible role
  label with no class label. The work-loop intake sweep's escalation proposes the role-label swap
  in place of a `Proposed work class:` line.
- The holds in triage, the work-loop drain and the attended queue read `provenance: untrusted` and
  `provenance: signal`; they no longer read the legacy `work-class: untrusted-provenance`, except
  the provenance-removal hold in the work-loop drain and the attended queue, which still asks who
  last removed it.
- `/work-items:setup` checks and provisions `provenance: untrusted` alone (`check` probe 7 and
  `apply` step 3); it no longer checks or creates the four `work-class:` labels.
