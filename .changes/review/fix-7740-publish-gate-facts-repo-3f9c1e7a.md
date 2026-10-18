---
bump: patch
---

### Security

- `explain-change` publish gates take the repository from the pull request's own URL in `facts.json`, never from a model-typed argument, so a mistyped public repository can no longer make a private pull request's diff publishable. `digest-policy.mjs --publish-gate` now takes `--facts <facts.json>` in place of `--repo`, and `publish-hosted.mjs` takes `--facts <facts.json>` in place of `--repo` and `--pr`. Its sidecar key, host included, comes from the same URL. In the gate, a missing facts file or one with no pull request URL gates as `UNKNOWN`. The hosted publisher publishes nothing in that case.
- The visibility lookup always names the URL's host, github.com included, so `GH_HOST` cannot send it to another server. Owner, name and number are checked the way `read-pr.sh` checks them.
- The skill reads the diff by the facts file's pull request URL, so the gated diff is the pull request whose visibility was looked up. A facts file the model wrote by hand, with no `source-control` plugin, keeps the page as a file.
