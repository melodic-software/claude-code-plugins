---
bump: patch
---

### Fixed

- A file the files API sends no patch for no longer holds for a person when its blob ids show no unread content: a rename, mode change or modification that keeps its blob and does not gain execute, or an empty file added or removed, scores the mergeable `no-patch:<path>`. Changed bytes, a copy, a mode that gains execute or an unread blob id still hold as `unreviewed-patch:<path>`. ([#10873](https://github.com/melodic-software/claude-code-plugins/issues/10873))
