---
bump: patch
---

### Fixed

- `work` and `work-loop` name each plugin file they send the model to as a `${CLAUDE_PLUGIN_ROOT}/...` path to open with one Read, never a Glob or Grep of the plugin directory: the bound adapter's README (`adapters/<provider>/README.md`, `<provider>` being the item id's prefix), `CONTRACT.md` for `branch_ref`, the `track` `done` and `recheck` actions, and `label-taxonomy.md` for the unread `work-class:` labels. The tracker seam reference names the adapter README by provider instead of for GitHub only.
