---
bump: patch
---

### Changed

- The rendered-view reference is now a synced copy of the one shared rendered-view procedure, and the shared medium resolver modules (`view-settings.mjs` and the modules it loads) ship under `lib/` ([#12667](https://github.com/melodic-software/claude-code-plugins/issues/12667)); no skill changes how it resolves the medium yet.
