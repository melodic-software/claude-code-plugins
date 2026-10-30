---
bump: patch
---

### Fixed

- The merge gate's risk scorer no longer holds a file the files API sends no patch for when its blob ids show no unread content: a rename, mode change or modification that keeps its blob, and an empty file added or removed, now score the mergeable MED `no-patch:<path>`. A mode that gains execute, a copy, changed bytes, and a missing or malformed blob id still hold for a person as `unreviewed-patch:<path>`. `changed_files` reads each side's blob id from the trees it already reads for modes. ([#10873](https://github.com/melodic-software/claude-code-plugins/issues/10873))
