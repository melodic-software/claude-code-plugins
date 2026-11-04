---
bump: minor
---

### Removed

- The one-release reads of the pre-YAML team and overlay files, added in 0.5.0. `scripts/resolve-config.sh` reads the team layer only from `docs-naming.yaml` and the overlay only from `docs-naming.local.yaml` under the convention home, never from `.claude/docs-naming.json`, `.claude/docs-naming.local.json`, or their retired `docs-hygiene` names, and `paths` no longer reports a `deprecated` state. Retirement records `docs-naming-r001` and `docs-naming-r002` are demoted to `report-only`. `/docs-naming:setup check` prints a WARN row for each old team or overlay file it finds. While the team YAML is absent, the first `/docs-naming:setup apply` still copies the old team file's keys into it and leaves that file in place. A repository that keeps its settings in an old file runs that write (or moves overlay keys by hand), then deletes the old file. The user-global `~/.claude/docs-naming.json` is still read ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737), [#12287](https://github.com/melodic-software/claude-code-plugins/issues/12287)).
