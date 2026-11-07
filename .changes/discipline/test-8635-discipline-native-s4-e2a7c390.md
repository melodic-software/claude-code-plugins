---
bump: patch
---

### Changed

- The sweep-all, reuse-or-replace, follow-our-standards and tighten-your-output skills' legacy `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): 15 new cases and graders added to 3 existing cases. Three sweep-all legacy cases are held on #8635: two need userConfig values a run cannot set, one needs the fork canary to fail. All four `evals.json` files are deleted.
