---
bump: minor
---

### Added

- `schemas/harness-config.schema.json`, the schema of a repository's `docs/conventions/harness-config.yaml`, the team layer of the plugin's settings; its `suppressions` mapping holds the deliberately kept findings of `/harness-config:audit` and `/harness-config:audit-pass`, keyed by `finding_id`.

### Changed

- **audit:** the engine reads the team suppression layer from the `suppressions` mapping of `<home>/harness-config.yaml` (`<home>` is the convention home the repository binds, else `docs/conventions`) with the shared YAML-subset parser, now carried as `lib/yaml-subset.awk`. The fenced block of `.claude/audit-pass.md` is read in its place only while that file is absent, for one release; with both present the old file is reported ignored, and a team YAML that does not parse drops the team layer instead of falling back to it.
- **audit:** the engine's `suppressions` object gains `layers`, naming the file each layer was read from and its state, and each applied entry names its source file beside its layer.
- **setup:** `check` probes and parses the team YAML and reports the old team file (WARN while the YAML is absent); `apply` writes the YAML from the old file's entries, unchanged, and scaffolds the YAML on request.
- **audit, audit-pass:** the skills and references point at the team YAML for reading and recording a suppression.
