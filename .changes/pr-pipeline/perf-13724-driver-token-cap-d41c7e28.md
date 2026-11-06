---
bump: major
---

### Changed

- **Breaking:** `pr-pipeline.schema.json` requires `merge.verify-capture.proxy.driver-token-cap`, so a `pr-pipeline.yaml` whose `proxy` lacks it fails validation; add it. It bounds the tokens the capture job's trusted driver legs may spend through the key proxy's loopback port, apart from `token-cap`, which now bounds only the driven session ([#13724](https://github.com/melodic-software/claude-code-plugins/issues/13724)).
