---
bump: patch
---

### Changed

- `babysit_verify_evidence.NEEDS_HUMAN` is `verify:untrusted-spec` alone (owner rule 2026-10-27: a person only for an intent or design change or a CRITICAL security issue, trust holds kept). `verify:repeated-fail` and `verify:too-old` still refuse the merge for good, now with no `needs-human` label: the pr-merge gate writes no escalation for them, and `enable-auto-merge.mjs` leaves the pull request unarmed with the lane comment and, once it stands, a failing `pr-merge/unarmed` status.

### Removed

- The repeated-fail escalation's quote of the head FAIL's summary, now unreachable: `babysit_merge._fail_summary`, `_carried_quote` and `VERIFY_SUMMARY_MAX`, `Reader.fail_summary`, `SummaryUnreadable`, and the report's `headFail` field.
