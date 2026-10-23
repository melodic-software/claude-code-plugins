---
bump: patch
---

### Fixed

- The post-merge check (`babysit_postmerge.py`) recognizes a native auto-merge of the agent identity's pull request: the newest auto-merge enable or disable event is the identity's enable, made no later than the merge-queue enqueue. Such a merge posts no `babysit-merge-pin` comment, so it no longer waits for a pin read-back and fails it at the dispatch deadline, which filed a demotion record and held pr-merge for owner and Dependabot pull requests. It is still the identity's merge, so post-merge-dispatch starts its full run, and it verifies on the dispatch and canary runs alone; a red full run or canary after it still fails it. The auto-merge events come from a second aliased `timelineItems` connection in the same merged-pull-request query, and a native merge skips the pin read, so no read is added. A gate merge keeps its read-back: the gate disarms an armed auto-merge before it pins, and an arm made after the enqueue does not count.
