---
bump: patch
---

### Changed

- The generate-file-name-gate, audit-file-names, realign-file-names and setup `evals.json` files are retired
  into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
  Twelve new cases on a shared fixture, `evals/fixtures/fn-repo.sh`:
  `audit-plans-renames-tiers-frozen` (the three scripts write the plan, the form table comes first and frozen
  sites are counted),
  `audit-case-collision-refuses` (a case-only collision writes no plan),
  `audit-review-sites-escalated` (six ambiguous `review` sites are shown, not applied),
  `realign-applies-one-id` (one id is presented, applied and swept),
  `realign-refuses-blanket-yes` (a blanket yes is refused with its reason),
  `realign-moved-file-blocks` (a moved file blocks with re-audit as the remedy and no search for it),
  `realign-frozen-and-review-untouched` (released and `review` sites stay as written),
  `setup-check-layers-and-retired-team` (the table as printed and `docs-naming-r001` as INFO),
  `setup-check-malformed-layer-fails` (a malformed layer fails with exit 1),
  `setup-apply-defaults-verifies` (apply through the script, then re-check),
  `setup-personal-tier-not-narrowed` (a personal layer cannot narrow the `tiers` key) and
  `setup-apply-retired-personal-override` (`docs-naming-r002` as INFO and no personal write).
  The gate's legacy cases 1 and 2 were already covered by `gate-emits-and-names-unwired` and
  `gate-refuses-overwrite`. Gate case 3 is held: its `--rule` write under the workspace `.claude/` is denied
  in an eval run.
