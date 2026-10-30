---
bump: patch
---

### Fixed

- `/planning:interview` recommendations now carry a `Flips if:` line after `Inference:` ([#11190](https://github.com/melodic-software/claude-code-plugins/issues/11190)). It names the condition that would change that recommendation, as a fact the user can confirm. Before, a round's one shared closing probe was the only invitation to name what would change an answer.
