---
bump: patch
---

### Changed

- ci-status's merge-queue step runs pr-merge's verdict reader (`babysit_verify_evidence.py evidence --base-sha`) from a checkout of main for a lanes App pull request at the head it merges, on a listing of its own, and holds on every FAIL class the gate counts, `verify:unreadable` and `verify:too-old` (`merge-holds.mjs` `evidenceHold`), so a FAIL uploaded after the pull request was armed still blocks it; a trusted approval of the head lifts the hold as it lifts a missing pass. A refusal the reader returns before it lists (`verify:too-old`, an unread config) holds the same way and the same approval lifts it. The reader starts from pr-merge's head-ref map and its `pr-merge-run-cache` artifact (`carry-run-cache.mjs read`; ci-status restores no Actions cache), so it makes about 73 requests where a cold reader makes about 860; with no carried run cache it reads cold only when GITHUB_TOKEN's core pool has 900 requests plus the `limits.api` read floor left (read once from `/rate_limit`), and holds otherwise; `ci-status`'s timeout is 20 minutes, up from 11, to fit a cold read. The pass names come from its listing in place of the four by-name lookups (`.github/workflows/pr-require-checks.yml`).
- enable-auto-merge reads the artifact listing once per run and shares it across its pull requests (`evidence --shared-listing`), where it listed again for each one its reader allowed and after every two minutes (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
