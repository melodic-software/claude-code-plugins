---
bump: patch
---

### Changed

- The six skills' `evals.json` files and the audit skill's three Markdown inputs are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Thirty-six new cases (`au-`, `ck-`, `dl-`, `mg-`, `ra-`, `su-`) cover the audit's demote and promote lanes, held-back safety rails, zero-match globs, coverage reporting and the content-home advisory; the check gate's failure statuses, missing index, over-broad warning and fail-closed exit; delta's quiet run, declined findings, broken globs, noise budget and suppression layers; migrate's plan-first split, shim removal gate and cutover evidence; realign's per-item gate, held-back items, staleness checks, shims and declines; and setup's reachability verdicts, optional prerequisites and configuration sources. Each is a described scenario graded on the reply. Legacy delta case 5 was already covered by `dl-no-baseline-routes-to-audit`.
