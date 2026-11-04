---
bump: patch
---

### Fixed

- `glob-tools.sh` reads a `paths:` pattern by its form, per the memory page: a pattern with no slash matches at any depth under the base, and a leading slash anchors it at the base. `/*.md` and `*.yaml` no longer report `zero-match` on files they match, and `*.md` now counts every `.md` file rather than the root's alone ([#10456](https://github.com/melodic-software/claude-code-plugins/issues/10456)).
- `glob-tools.sh rules` matches each rule's patterns from its base, the directory holding its `.claude` folder. A nested rule whose patterns match only outside that directory now reports `zero-match`, and a base-relative pattern such as `src/*.ts` no longer does when the file sits under that base.
- `ip_parse_paths` reads `paths:` written as a comma-separated string, so `check`, the index and `detect.sh` no longer see such a rule as unscoped.
- The import walk in `lib/discover.sh` keeps a backslash-escaped space inside the path and does not count a path wrapped in quotes as an import, so the reachability verdict matches what Claude Code loads.
