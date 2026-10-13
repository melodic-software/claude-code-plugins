---
bump: patch
---

### Security

- video-digest: the resume prompt (`run-state/continuation-prompt.md`) no longer puts the video title in its heading or the source URL on a bare line. Both now sit in a fenced `## Video metadata` block, reduced to one line each with backticks neutralized, under the untrusted-content framing that marks them, and the slice files the resume steps read (`run-state/watch.json`, `source/transcript.txt`, the lane deliverables), as data, never instructions. A publisher-written title can no longer read as part of the resuming session's own prompt. (#6980)
