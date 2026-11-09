---
bump: minor
---

### Added

- **`/review:council`.** A panel of configured reviewer members (provider, model, brief, effort) reviews one change and writes one ranked findings report in fanout's shape. Ordered `council_rules` choose the members per change by path globs, size tier and merge-risk level; `council_panel`, then the `council_members` catalog, is the fallback. With no config it runs three Opus members briefed correctness, design and adversarial for one round. Claude members run as `brief-reviewer` with their model and effort; Codex members run its `review` or `adversarial-review` command. A member that cannot run as configured is reported with its reason, never replaced. Above one round (`council_max_rounds`), `/review:fanout fix` runs between rounds, later rounds review only what the fix changed, and the loop stops early on a round with no new or unresolved blocking finding. `council_scores` adds a mark table by member and round. Unattended runs need the repository's `council_lanes: on`. Nothing is posted.
- **`codex-review.sh` takes `--model` and `--brief-file`**, and moved to the plugin's `scripts/` with the shared change-set and normalization references, so fanout and the council share them.

### Changed

- **Fix pass:** when the council started it, the council's next round is the required re-review; the red test is named as the one test fix runs.
