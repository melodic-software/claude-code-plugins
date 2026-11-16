---
bump: minor
---

### Added

- The git-hook installer reads two new `entries.json` fields. `earlierEntries` (`[{"from": <old entry>, "to": [<entries>]}]`) reports what an install of a split or renamed entry left as superseded drift, and carries a decline of the old entry to every entry it became. `resolved: true` on an entry takes its tools from the entry script's `--resolve` rows, which read records and run none, so a missing-tool decision names the tool the repository actually resolves. A top-level `ecosystems` list names the ecosystem records the entries bind.
