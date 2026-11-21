---
bump: none
---

### Changed

- **An eval case drops its Read-tool workaround.** The `eb-export-map-already-enforces` case's
  scaffold no longer tells the run to read files outside the repository with the Read tool. A
  denied shell read of the plugin copy that no grader reads is now counted under the evals plugin's
  counted-denial rule. No release: the change is to an eval case, not to a shipped skill.
  ([#17019](https://github.com/melodic-software/claude-code-plugins/issues/17019))
