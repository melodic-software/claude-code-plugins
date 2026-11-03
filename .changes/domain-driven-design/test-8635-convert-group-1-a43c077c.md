---
bump: patch
---

### Changed

- The legacy `skills/curate-language/evals/evals.json` is converted and removed: its five scenarios the `cl-*` suite already covers are dropped, and its other three become `evals/curate-language-*` cases beside it (attended glossary proposal, no empty or fixed-name file, passive lookup) ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- `/domain-driven-design:curate-language` records a name the resolution rules out ("never the X") as a rejected synonym in the file's convention, not inside the definition.
