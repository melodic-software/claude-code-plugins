---
bump: patch
---

### Fixed

- An `address-feedback` fix commit now names the review threads it fixes. `apply-patch.mjs` adds a `Lane-Thread: <thread id>` line after the `Lane-Activity` trailer for each kept thread that a `VALID` reply in the scanned replies names, under the `review-threads` row's new `thread-trailer` key. A reply that names a thread the select job did not keep adds no line. The push job downloads those replies before the mint (the write workflow's new `patch-replies-attempt` and `patch-replies-sha256` inputs) and fails red unless their SHA-256 is the scan job's. `publish-feedback` credits a fix commit to a thread only when the commit's `Lane-Thread` lines name it, in the same round and on a retry's earlier fix alike. A `VALID` thread that no trailer names ends the round `feedback-not-landed`. Before this change, a sibling commit that fixed another finding in the same file could be credited, and the thread resolved, while its own finding stood. Lane fix commits made before this change carry no `Lane-Thread` lines, so a retry no longer credits them.
