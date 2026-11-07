---
bump: patch
---

### Changed

- The principles and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). 18 new cases cover every legacy case.
  - The setup `gradle-project` fixture becomes a scaffold's heredoc, and the other setup cases seed a repository from `evals/fixtures/seed-shipping.sh`.
