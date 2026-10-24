---
bump: patch
---

### Fixed

- `enable-auto-merge` posts the gate's `<!-- babysit-merge-pin sha=<head> -->` comment before it arms a lanes App pull request, unless the App's newest pin already names that head unedited. When the pin fails to post, the pull request stays unarmed and the run fails. Arming a pull request that is already mergeable enqueues it at once with no auto-merge event, so the post-merge check now reads that head back against the pin.
