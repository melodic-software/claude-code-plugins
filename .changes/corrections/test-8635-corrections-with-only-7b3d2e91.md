---
bump: patch
---

### Changed

- `codify-person-note-appends-row-from-file` scores `runs-buffer-append` and `appends-from-file-and-reports` in the with-plugin arm only, because the no-plugin baseline cannot call the plugin's bundled `buffer.sh`.
