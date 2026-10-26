---
bump: patch
---

### Fixed

- pr-merge's `merge` and `enable-auto-merge` jobs no longer restore an Actions cache. They hold `id-token: write` and the lanes App token, and they restored the carried verdict reads by the bare prefix `pr-merge-run-cache-`. Any job in the default branch's cache scope can write that prefix, and the pinned restore extracts its archive into the workspace with no entry filter, so a crafted entry could replace a checked-out script before it ran (#9455). The carried reads and skippable refusals now travel as the `pr-merge-run-cache` artifact (`.github/scripts/pr-merge/carry-run-cache.mjs read`). Each job reads it from the newest scheduled or hand-started `pr-merge.yml` run on main whose head commit is on main, found the way the head-ref map is. The read removes any file at its path before it starts. The carried sections are still used only to count a FAIL. Only a scheduled or hand-started `merge` job uploads the file, since no other run's copy is read back, so a `pull_request_target` run no longer passes its reads to the next run. Permissions are unchanged.
- A workflow test fails when a job holding `id-token: write` or a lanes App token restores a cache by a `restore-keys` prefix in any workflow, local composite actions included. A second test fails when a token-holding job in `pr-merge.yml` restores any cache.
