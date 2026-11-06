---
bump: patch
---

### Fixed

- `/harness-ops:changelog apply --ci` writes `ci-plan.json` once its rows are decided and rewrites it after native drift and after each committed branch, so a run stopped at its turn cap or timeout still publishes the branches it finished and files every other row, instead of leaving no plan ([#7407](https://github.com/melodic-software/claude-code-plugins/issues/7407)).
