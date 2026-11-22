---
bump: minor
---

### Added

- A `role_map_file` option (type `file`) names your own role map file, the user layer of the config cascade. `/multi-agent:route` and `/multi-agent:setup` pass it to the resolver, and `/multi-agent:setup apply --layer user` writes to it. A leading `~/` expands against your home; any other path that is not absolute is refused by `setup` and skipped with a note by the resolver ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).
- `/multi-agent:setup apply --migrate` moves each old file into its new location after a preview and a yes: `~/.claude/multi-agent.yaml` into the `role_map_file` file, `.claude/multi-agent.local.yaml` into `<home>/multi-agent.local.yaml`, and a retired `.claude/multi-agent.yaml` into the team YAML. A key the new file already sets keeps its value and is named. The command reads the new file back and checks the layers still resolve the same values before it deletes the old file ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).

### Changed

- The personal override is now `<home>/multi-agent.local.yaml`, and `setup check` recommends the `<home>/**/*.local.*` ignore line. An old `~/.claude/multi-agent.yaml` or `.claude/multi-agent.local.yaml` is still read while its new file is absent. Each run names each old file in `notes`, with its new location and the migrate command. `setup apply --layer user` and `--layer local` refuse while that layer's old file exists ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).
