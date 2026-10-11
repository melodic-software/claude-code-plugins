---
bump: patch
---

### Changed

- **Shared `parse-concern-value.sh` synced, with its parser `yaml-subset.awk` beside it.** The reader takes dotted keys, `--list`, stdin (`-`), a validated `--ref` and `--strict`; every existing root-key read resolves as before, and a file the parser rejects now yields the fallback with one stderr line.

### Fixed

- **The shared `yaml-subset.awk` refuses a tab indent and an unquoted colon followed by a space in a value (`key: a: b`).** Both parsed before although a YAML loader rejects them; a file holding either now reads as a parse error, so quote a value that holds a colon followed by a space. A tab in a markdown fence's base indent is still accepted.
