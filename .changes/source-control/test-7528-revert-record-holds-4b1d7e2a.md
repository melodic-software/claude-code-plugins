---
bump: patch
---

### Changed

- `read_demotion` tests cover the `revert` demotion record that `post-merge-demotion-alert.yml` now files when a push to main reverts a pull request the lanes App put in the merge queue: it holds the rung off while open, clears only when a person closes it directly, and a later green main run does not clear it. No change to the plugin's behavior.
