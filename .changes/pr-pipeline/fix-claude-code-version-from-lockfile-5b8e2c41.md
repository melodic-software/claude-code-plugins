---
bump: minor
---

### Removed

- `merge.verify-capture.proxy.claude-code-version`. pr-verify-capture installs the Claude Code version main's `package-lock.json` pins and hands it to both driver legs, so a version bump needs no edit to pr-pipeline.yaml. The proxy's `betas`, `body-keys` and `block-types` lists stay as measured; the proxy refuses a value they do not list and names it.
