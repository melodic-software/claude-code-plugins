---
bump: minor
---

### Changed

- **`setup` writes the YAML settings files.** `apply` writes the team layer to `<home>/attribution.yaml` and the local overlay to `<home>/attribution.local.yaml`, `<home>` being the convention home that `lib/resolve-convention-home.sh` prints, else `docs/conventions`. While the convention-home pointer is broken, it writes neither file. Before the first write to a layer still on its `.claude/` JSON fallback, it carries every key of that JSON into the new YAML file, because the detectors stop reading the JSON once the YAML exists. It checks that the overlay is gitignored before writing it, and its key examples are block-style YAML that cites `schemas/attribution.schema.json`.
- **The README and the audit skill name the YAML files as what `setup` manages.** The README's key example is YAML, in place of the JSON form.
- **`attribution-r001` and `attribution-r002` migrate into the YAML files.** Their `successor` prose named `.claude/attribution.json` and `.claude/attribution.local.json` as the destinations; it now names `<home>/attribution.yaml` and `<home>/attribution.local.yaml`, and a key the current layer already sets keeps its value. The detection fields are unchanged.
