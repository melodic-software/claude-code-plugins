---
bump: patch
---

### Fixed

- The pr-verify verdict reader (`babysit_verify_evidence.py`) no longer pages three whole artifact listings when a whole listing's top-up holds more artifacts than GitHub's live count, which a further whole listing cannot cure since each one only adds ids. It refuses `verify:unreadable` after the first, as before after the third. Under-count misses, the page-boundary skips a further listing restores, keep their three reads.
- A listing that fails after it began a whole listing is noted beside the job's saved listing, and every later reader in the job refuses on that note without paging, in the same process or another. A failure for want of a caller's time is not noted: when a caller's limit (`BABYSIT_VERIFY_DEADLINE_SECONDS`) cut the listing's timeout and the listing ran out of it, the refusal starts with the caller-limit detail, so pr-unblock `verify-cap.mjs` skips the round for that run, and a later reader with more time still lists. On 2026-11-01 between 08:00Z and 09:00Z, GitHub's count dropped artifacts up to an hour before the `expires_at` it listed. Each lanes merge-queue ci-status job then paged three whole listings, about 450 calls, and each pr-merge `merge` job paged them once per candidate, 825 to 1,015 calls.
