---
bump: patch
---

### Changed

- The unattended merge reads the `merge:` block and `babysit_loop_merge` at the default branch head as well as at the pull request's base SHA and takes the stricter value of each setting, so a tightening on the default branch reaches pull requests opened before it; the two must name the same agent identity and enable the same authority ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
