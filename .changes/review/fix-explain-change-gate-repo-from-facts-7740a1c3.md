---
bump: patch
---

### Fixed

- `explain-change` artifact gate: it reads the repository from the pull request's own `url` in `facts.json` and looks up that repository's visibility, instead of trusting a `--repo` the model types. `digest-policy.mjs --publish-gate` now takes `--facts <facts.json>`; a `--repo` that differs from the facts' repository refuses, and missing facts, a URL that is not a pull request's, or a failed lookup gate as `UNKNOWN`.
