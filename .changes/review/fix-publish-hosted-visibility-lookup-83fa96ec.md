---
bump: patch
---

### Fixed

- `/review:explain-change` on `medium: hosted`: `publish-hosted.mjs` looks up the repository's visibility itself through `gh api repos/<owner>/<repo>` and no longer takes `--repo-visibility`, so a wrong visibility from the caller can no longer send a private repository's page to the public host. A failed, slow or unexpected lookup sends the page private.
