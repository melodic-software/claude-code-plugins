---
bump: patch
---

### Changed

- The script-the-deterministic-work and setup skills' legacy `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): 15 new cases and one scaffold fixture (`evals/fixtures/su-repo.sh`). Two legacy cases or parts are held on #8635: both need userConfig values a run cannot set. Both `evals.json` files are deleted.
