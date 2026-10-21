---
bump: patch
---

### Fixed

- leave pending merge records unwritten on report-only pr-merge runs

  A merge.report-only unattended --merge run read the recorded merge-queue
  or async merge entry and cleared or rewrote it, so the live run that
  dispatches the post-merge full run found no record. Report-only runs now
  leave the pending merge record as it was; the report is unchanged.
