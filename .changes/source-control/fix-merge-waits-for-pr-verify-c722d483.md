---
bump: patch
---

### Fixed

- `/source-control:pull-request merge` waits for pr-verify's verdict at the pinned head before it merges or enqueues, in a repository that runs pr-verify and for an author pr-verify judges. It reads the four pass names the merge queue's CI Status step reads, waits up to 30 minutes while pr-verify has not judged the head, and holds on a FAIL (the `pr-verify-failed` label), a moved head or a failed read. A PR queued before its verdict was removed from the merge queue when pr-verify then failed it.
