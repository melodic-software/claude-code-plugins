---
bump: minor
---

### Added

- `/knowledge:absorb-upstream` reads one outside source, a GitHub repository at a pinned commit or one web page or post, and writes a tracked `docs/upstream/` record. Each row gives what an idea does; the upstream's problem, motivation and goal in our own words, labelled Stated or Inference, with a link at the pin; our matching problem; and a take, adapt, already-have or reject disposition with the reason. The record also carries the pin marker, the recheck trigger and a licence notice, holds no quoted or paraphrased upstream text, and the skill stops instead of overwriting an existing record.
- `upstream_records_dir` in `<home>/knowledge.yaml` (default `docs/upstream`, overridden for one run by `--out`) sets where the record lands, with its schema at `schemas/knowledge.schema.json` and its contract at `reference/config.md`. `/knowledge:setup check` reports the directory and its layer, and names an invalid value.
