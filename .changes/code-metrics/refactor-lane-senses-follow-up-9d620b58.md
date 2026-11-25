---
bump: major
---

### Changed

- **Code-metrics groups files by language, not by lane.** "Lane" now means only a worker that
  serves one pipeline stage. The `docs/conventions/code-metrics.yaml` key is `languages` (rename a
  `lanes:` key to `languages:`, with no alias), report rows carry `language`, the duplication
  summary is `by_language`, the type-debt total row is labeled `language-total`, `unavailable`
  lists `language/measure`, and `scripts/detect-lanes.sh` is `scripts/detect-languages.sh`. The
  dispatcher's `--disable-lane` and `--lane-globs` are `--disable-language` and
  `--language-globs`.
