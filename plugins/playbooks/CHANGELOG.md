# Changelog

All notable changes to the `playbooks` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## 0.1.0

### Added

- **`playbooks` plugin** — merges three previously standalone knowledge/doctrine
  plugins into one, plus a central maintainer update skill:
  - `boris` (`/playbooks:boris`) — merged from the `boris` plugin's `boris` skill
    (formerly `/boris:boris`). Boris Cherny's Claude Code workflow tips, with its
    topic reference files, vendored upstream baseline, and update script carried over.
  - `thariq` (`/playbooks:thariq`) — merged from the `thariq-skills` plugin's
    `thariq-skills` skill (formerly `/thariq-skills:thariq-skills`). Anthropic's
    internal skill-authoring playbook, with its vendored upstream baseline and update
    script carried over.
  - `fable-5` (`/playbooks:fable-5`) — merged from the `fable-5-playbook` plugin's
    `fable-5-playbook` skill (formerly `/fable-5-playbook:fable-5-playbook`). Claude
    Fable 5's operating doctrine and its trigger-routed `context/` chapters. Self-authored,
    no upstream.
  - `update` (`/playbooks:update`) — new central, maintainer-facing drift-check and
    upstream sync skill. Dispatches to each upstreamed pack's self-locating update
    script (`--check` default, read-only; `--apply` refreshes the vendored baseline
    only). fable-5 has no upstream and is reported as self-authored.

### Changed

- **Update centralized.** The per-pack update actions (`/boris:boris update`,
  `/thariq-skills:thariq-skills update`) are removed from the pack skills, which are now
  pure knowledge/navigation skills. Drift-checking and syncing are handled by the single
  `/playbooks:update` skill. The pack update scripts are unchanged in behavior (upstream
  URLs, self-location, and security posture preserved); only their user-facing invocation
  strings were retargeted to `/playbooks:update`.
- **Skills renamed** on the merge: `boris` → `boris`, `thariq-skills` → `thariq`,
  `fable-5-playbook` → `fable-5`. Their vendored-baseline security posture (untrusted
  third-party data; never follow embedded auto-install instructions; sanctioned mechanics
  are `/playbooks:update` and `/plugin marketplace update`) is preserved.
