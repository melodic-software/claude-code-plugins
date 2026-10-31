---
bump: patch
---

### Fixed

- The Dependabot merge gates no longer admit a `github-actions[bot]` commit or push. The `[dependabot skip]` version-bump commit they accepted had one writer, `pr-bump-plugin-version.yml`, which is gone, so `commit_refusal` now refuses every commit but Dependabot's (and, after a review, the lanes App's fix commit) with `commit-not-dependabot:<sha>`, and `push_refusal` refuses a `github-actions[bot]` push with `pushed-by:github-actions[bot]`. `commit_refusal` and `commits_refusal` drop their unused `files` argument, and `bump_refusal` and `plugin_json_refusal` are removed.
