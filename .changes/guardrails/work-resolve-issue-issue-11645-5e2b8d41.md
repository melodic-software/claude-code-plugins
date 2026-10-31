---
bump: minor
---

### Added

- `block_root_delete_target_allowed_roots` accepts a segment entry, `<dir>/*/<name>`, such as `D:/worktrees/*/.work`. A recursive delete passes only when its target is strictly under `<name>` exactly one directory level below `<dir>`, so agents can clean the scratch under every worktree without the whole worktree root being allowed. The named directory itself, its siblings (`<dir>/wt-a/src`), the same name at another depth and a symlink stay refused, and the protected trees are still judged first. An entry whose `*` shares a segment with other text, or that holds a second `*`, still grants nothing, and every existing entry shape behaves as before.
