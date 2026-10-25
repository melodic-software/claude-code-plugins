---
bump: minor
---

### Added

- A repository's own findings-buffer adapter can be bound in user scope, through two new `userConfig` options: `findings_buffer_adapter_repository`, the git common directory of the one repository it applies to, and `findings_buffer_adapter_path`, the adapter directory relative to the checkout root. `buffer.sh` reads them from user and managed settings only, never from the environment, a project settings file or the repository's binding files, which still name only adapters the plugin ships. The binding applies in that repository's main checkout and its worktrees and in no other repository, and the adapter must resolve inside the current checkout, outside any nested repository, and pass the existing verb and `capabilities.json` checks.
- A generated copy of the shared `lib/plugin-options.mjs` settings reader, under `scripts/lib/`.
