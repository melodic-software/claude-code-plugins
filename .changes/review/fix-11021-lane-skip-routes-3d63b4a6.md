---
bump: patch
---

### Changed

- Shared `publish-gate.mjs` synced: its GitHub and Anthropic token shapes are now one shared list (`CREDENTIAL_SHAPES`) that the issue lane's patch check also imports, each the broader of the two shapes the scanners held, so an `sk-ant-` key glued to a preceding word and a fine-grained `github_pat_` token of 22 or more characters now keep a page local. No other change to this plugin.
