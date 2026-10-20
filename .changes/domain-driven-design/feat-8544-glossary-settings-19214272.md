---
bump: minor
---

### Added

- **Glossary file-name settings.** `glossary_file` (default `GLOSSARY.md`) and `glossary_map_file` (default `GLOSSARY-MAP.md`) resolve through the config cascade: the plugin default, `userConfig`, the team file `docs/conventions/domain-driven-design.yaml` and the personal overlay, validated by `schemas/domain-driven-design.schema.json`. `scripts/glossary-settings.mjs` reports the layer that supplied each name and drops a layer whose value is a path rather than a file name.

### Changed

- **`/domain-driven-design:curate-language` proposes a glossary layout when the repository has none.** It proposes one `glossary_file` per bounded context, opening with a short description of the context, and one `glossary_map_file` at the repository root once more than one context exists. An attended run asks before writing; an unattended run still writes nothing and reports the missing convention. The skill also states that framework and tooling nouns belong in the architecture docs, not the glossary.
