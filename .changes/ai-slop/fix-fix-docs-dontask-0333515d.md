---
bump: patch
---

### Security

- `detect.sh` and `rubric-fanout.sh` run every git call with `core.fsmonitor` and hooks turned
  off, so a target repository's own config cannot make an audit run a program. A probe of the
  fix-docs lane showed a nested repository's `core.fsmonitor` running under
  `detect.sh --list-targets`
  ([run 39782588972](https://github.com/melodic-software/claude-code-plugins/actions/runs/39782588972)).
