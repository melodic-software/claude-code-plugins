---
bump: patch
---

### Changed

- **Shared `parse-concern-value.sh` synced, with its parser `yaml-subset.awk` beside it.** The reader takes dotted keys, `--list`, stdin (`-`), a validated `--ref` and `--strict`; every existing root-key read resolves as before, and a file the parser rejects now yields the fallback with one stderr line.
