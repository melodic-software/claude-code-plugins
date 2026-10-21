---
bump: major
---

### Changed

- **BREAKING:** the bundled YAML-subset reader (`yaml-subset.awk`) now refuses a flow mapping (`key: { a: 1 }`, `{}`, or a `{...}` item in a list) and a line opening with a `---` or `...` document marker, as the stricter `yaml-subset.mjs` grammar does. The error names the line and says to use block style; each caller adds the file. A `docs/conventions/*.yaml` file or `yaml config` block that used either one no longer parses, and its reader falls back to defaults until it is rewritten in block style, one key per line.
