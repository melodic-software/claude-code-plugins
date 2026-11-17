---
bump: minor
---

### Added

- The git-hook installer reads two new `entries.json` fields. `earlierEntries` (`[{"from": <old entry>, "to": [<entries>]}]`) reports what an install of a split or renamed entry left as superseded drift, and carries a decline of the old entry to every entry it became. `resolved: true` on an entry takes its tools from the entry script's `--resolve` rows, which run nothing, so a missing-tool decision names only an adapter tool the repository's own config opts in to. A top-level `ecosystems` list names the ecosystem records the plugin's setup reports.
