---
bump: patch
---

### Changed

- illustrate: the builder takes the model by `--model <file>` (stdin still works), and the skill writes the model to `illustrate/models/<slug>.json` under the plugin data directory instead of passing it in a heredoc, so no topic text becomes part of a shell command. The video offer passes `/explainer-video:produce` only the record's path, leaving where the video goes to that skill. (#6110)
