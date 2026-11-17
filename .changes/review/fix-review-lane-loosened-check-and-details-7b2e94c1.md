---
bump: minor
---

### Changed

- `code-review` applies the loosened-check criterion to every changed file. It takes the verdict and patterns from the prompt's value lines when the wrapper writes them, else `fail` with no consumer entries, and treats the closing-issue text as the only spec.
- `code-review` folds its `Pre-existing (advisory):` and `manifest <field>:` summary lines into one `<details>` block after the findings and before the verifier line; `security-review` folds its `manifest <field>:` lines the same way and keeps `critical-findings: <n>` outside the block.
