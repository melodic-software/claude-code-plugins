---
bump: minor
---

### Added

- The team layer now lives in `docs/conventions/docs-naming.yaml` (under the repository's convention home) and the personal overlay in `docs/conventions/docs-naming.local.yaml`, validated by the new `schemas/docs-naming.schema.json` ([#9731](https://github.com/melodic-software/claude-code-plugins/issues/9731)). The keys are top-level keys of the file, with no `schema` or `file_names` wrapper.
- `scripts/resolve-config.sh paths` reports a layer read from the pre-YAML location as `deprecated`, and `/docs-naming:setup check` shows it as a WARN row.

### Changed

- `scripts/resolve-config.sh` reads the YAML first. For one release a team or overlay layer whose YAML is absent is read from the JSON file under `.claude/` it used to live in; the YAML wins whenever it exists and the two are never merged. The user-global layer stays a JSON file.
- `/docs-naming:setup apply` writes the YAML, seeds it on the first write from the JSON team layer the resolver reads in its place (the pre-YAML file, else the retired `docs-hygiene` one, which apply no longer refuses) so a fresh file never shadows those settings, and keeps the comment block at the top of an existing file. The retirement records and `/docs-naming:setup check` now point a retired file's settings at the YAML. `/docs-naming:setup check` follows the layer files the resolver names, and recommends the overlay gitignore line beside the overlay.
- `reference/config.md`, the README and the setup skill describe the YAML layers and the one-release fallback.
