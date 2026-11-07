---
bump: patch
---

### Changed

- The scrutinize-dont-coast, point-dont-copy, wait-what, recheck-against-upstream, mind-your-maxims and pick-for-the-problem skills' legacy `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): 22 new cases and graders added to 4 existing cases. Three recheck-against-upstream legacy cases are held on #8635: they need network access to fetch upstream docs. All six `evals.json` files are deleted.
