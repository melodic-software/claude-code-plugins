---
bump: minor
---

### Added

- `/source-control:pull-request media <pr> --manifest <file>` places a produced reviewer walkthrough in a marked `## Reviewer media` section near the top of the PR body: the video on top, then the contact sheet, chapter start times and screenshots in collapsed sections. It rewrites only the text between `<!-- reviewer-media:start -->` and `<!-- reviewer-media:end -->`, attaches only the files the producer's `manifest.json` lists with `gh pr edit --attach`, and links the Actions artifact with its expiry date when it cannot attach. It posts nothing on a leak-scan hit, a screenshot with no frame-text sidecar, a claim held by another run, a body that changed under the edit, or no way to host the media.
- `media claim` removes the request label and writes a claim line for the head commit before a build; `media fail` releases the claim, adds the failure label and posts one failure comment per commit; label names come from flags and `false` turns one off.
- Every file `media` uploads is bound to the producer's scan: the staged copy must match its manifest `sha256`, and each screenshot names its own frame-text sidecar with `sidecar_sha256`. An edit a person makes to the body while the upload runs is kept.
- `push-branch.sh` marks a reviewer-media section that shows an older commit `Out of date: shows commit <sha>` once a push succeeds, finding the PR by its head branch; `monitor` and `ready` make the same check.
- `prerequisites.json` declares Python 3.11+ as optional for the pull-request skill.
