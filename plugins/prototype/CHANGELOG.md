# Changelog

All notable changes to the `prototype` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Added

- **Composition table.** The shared discipline now maps the prototype to its upstream and
  downstream workflow skills — `/planning:prd`, `/improve-architecture:improve-architecture`,
  `/planning:architect`, and `/implementation:implement` — each invoked only when the sibling
  plugin is installed.
- **Named handoff capability in the auto-invoke gate.** The gate's "checkpointing your current
  work first" now names `/session-flow:handoff` (when installed) as the checkpoint capability.
