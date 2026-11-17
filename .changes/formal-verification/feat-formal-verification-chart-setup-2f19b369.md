---
bump: minor
---

### Added

- The `formal-verification` plugin, off by default.
- `/formal-verification:chart` model-checks a TLA+ spec with TLC and writes a Mermaid chart of its states and a report with the shortest path to each broken rule. Its scripts take the jar, Java and bounds as arguments and install nothing.
- `/formal-verification:setup` checks the script runtime, Java, the model checker and the renderer, and on a typed `apply install-model-checker` or `apply install-renderer` downloads the pinned file into the plugin data directory, keeping it only when its checksum matches.
- `reference/formal-skill.md`, the contract for a consumer's `formal-<area>` skill: its sections, one `sync.yaml` entry per check, the view file the chart reads, and where model files and unattended writes may go.
- Version pins and default bounds as keys of the consumer's `docs/conventions/formal-verification.yaml`, and the jar, Java and script-runtime paths as plugin options.
