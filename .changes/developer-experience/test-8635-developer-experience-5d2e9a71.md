---
bump: patch
---

### Changed

- The audit-tools, build-cli and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): five of the seven legacy cases were already covered by existing cases, one setup case is dropped because the skill cannot be model-invoked, and a new `review-app-start-handles` case grades a build-cli review of a command whose child process inherits the caller's stdin, stdout and stderr. All three `evals.json` files are deleted.
