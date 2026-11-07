---
bump: patch
---

### Changed

- The do-your-research and reason-dont-recite skills' legacy `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): 16 new cases and one scaffold fixture (`evals/fixtures/dyr-gateway-seed.sh`). Two legacy cases or parts are held on #8635: one needs network access to fetch upstream docs, one needs a subagent to fail. Both `evals.json` files are deleted.
