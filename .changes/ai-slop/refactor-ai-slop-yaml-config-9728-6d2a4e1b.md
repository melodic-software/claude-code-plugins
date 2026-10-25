---
bump: minor
---

### Changed

- The ai-slop audit reads its team settings from `docs/conventions/ai-slop.yaml` and its personal
  overlay from `docs/conventions/ai-slop.local.yaml`, in the convention home the repository binds,
  validated by the new `schemas/ai-slop.schema.json`. The older JSON files in `.claude/` are read
  only when the YAML beside them is absent, for one release; when both exist the YAML wins.
- `detect.sh --show-config` ends each effective value with `[layer: <file>]`, the layer that supplied
  it, or `[layer: default]` when none did.
- `/ai-slop:setup` writes the YAML team file and offers to carry an existing JSON file's values into
  it, turning the JSON `_comment` text into YAML comments. The README and the audit and setup skills
  describe the YAML location.
- The user-global JSON layer is unchanged in this release.
