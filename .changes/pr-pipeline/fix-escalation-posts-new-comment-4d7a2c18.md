---
bump: patch
---

### Fixed

- `enable-auto-merge` posts a new refusal comment when it escalates a lanes App pull request to a person (the comment carrying the attended queue's escalation marker, written with the human-gated label), instead of editing its earlier lane comment. An edit sent no notification and kept the comment's old date, so the timeline showed only a bare label event with no visible reason. A refusal that stays a lane's still edits the one comment in place, and an unchanged person's refusal is not posted again.
