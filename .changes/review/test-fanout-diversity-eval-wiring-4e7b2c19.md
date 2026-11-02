---
bump: none
---

### Added

- Eval cases `fanout-diversity-<fixture>-<arm>` for `/review:fanout run-everything`: four fixtures (`null-user`, `empty-ratings`, `short-title`, `search-sqli`) built from existing review-case scaffolds, each under four arms (`lens`, `model`, `model` plus Codex, `lens` plus Codex). Each case has an arm-check regex grader and recall and false-positive judges on the persisted report. `evals/fanout-diversity.md` states the case layout, the ground-truth file and the grader templates for the fixtures still to come.
