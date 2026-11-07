---
bump: patch
---

### Changed

- The generate and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Four new cases: `gen-search-archive` (a search over an archived briefing finds the item and starts no collection), `gen-two-weeks-markdown` (a natural two-week ask plans a markdown briefing over about 14 days and runs no slide build), `gen-merge-open-window` (a continued run merges new items into the existing tiers instead of appending a delta section) and `gen-candidate-batch-ranking` (the apolitical filter and the pragmatic ranking over a pre-collected batch). `gen-collected-material` gains graders for source states, the red-flag caveat and the Atlas 2 citation. The retro, bookmark, rendered-view and setup cases are held: each reads or writes the plugin data directory, which an eval run refuses. Both `evals.json` files are deleted; the archive fixture moves to `evals/fixtures/`.
