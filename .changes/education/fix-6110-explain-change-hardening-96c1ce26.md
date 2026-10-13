---
bump: patch
---

### Changed

- illustrate: the builder takes the model by `--model <file>` (stdin still works), and the skill writes the model to `illustrate/models/<slug>.json` under the plugin data directory instead of passing it in a heredoc, so the model's text never becomes part of a shell command, and the slug in that command is limited to lowercase letters, digits and hyphens. The video offer passes `/explainer-video:produce` only the record's path, leaving where the video goes to that skill. (#6110)
