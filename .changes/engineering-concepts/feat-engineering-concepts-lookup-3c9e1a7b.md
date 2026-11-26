---
bump: minor
---

### Added

- The `engineering-concepts` plugin: shipped software engineering concepts kept as data, one JSONL file per topic under `data/`, each record a pointer to the concept's official source rather than a copied definition. `scripts/lookup.mjs` finds records by id, name or alias (a merged id kept as an alias redirects), filters by topic, concern, kind, stage and reversibility, drops records by id or topic with `--exclude`, applies `--source-bar`, and prints each record as a JSON line with its counterweights and conflicts named. `--check-sources` fetches each official source and marks an unreachable one for re-sourcing without dropping the record. A malformed record is reported on stderr with its file and line while the rest load. The `source_bar` and `exclude` settings resolve through the plugin config cascade (the plugin options, then `docs/conventions/engineering-concepts.yaml` and its `.local.yaml`): the highest valid `source_bar` wins, an invalid one falls back to the default, and every layer's `exclude` list is unioned. The `/engineering-concepts:lookup` and `/engineering-concepts:load` skills drive it. The plugin installs disabled, and no curated records ship in this release.
