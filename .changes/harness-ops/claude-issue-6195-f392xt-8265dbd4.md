---
bump: patch
---

### Fixed

- **The `/harness-ops:plugins` sync self-update note names the right plugin.** When a run updated `harness-ops` itself along with other plugins, the note took the first moved row and could name another plugin, such as "this run updated architecture". The digest now carries a `self_update` row (`id`, `scope`, `old`, `new`) for this plugin's own moved record, and the note reads its name and versions from that row. A golden covers a run where this plugin's row is not the first update.
