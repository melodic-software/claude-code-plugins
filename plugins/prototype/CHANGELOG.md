# Changelog

All notable changes to the `prototype` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.0]

### Changed

- **BREAKING: both skills renamed** (fleet conformance wave — naming grammar, verb-first
  skill names). `/prototype:logic` is now `/prototype:pressure-test`; `/prototype:ui` is
  now `/prototype:explore-directions`. Update any saved invocations. Skill behavior,
  triggers, and evals are unchanged; only the leaf names and namespace tokens changed.

## [0.2.4]

### Changed

- README declares the Bash requirement of the bundled ecosystem-detection
  script with its Windows path (Git Bash) and documents the no-Bash degrade
  (detection reports "none detected"; the skills read the host project
  directly) — cross-platform declaration wave.

## [0.2.3]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.2.2]

### Changed

- Synced the composition table's sibling-skill routes to the reorganized plugin
  taxonomy: `/improve-architecture:improve-architecture` is now `/architecture:improve`.

## [0.2.1]

### Added

- **Composition table.** The shared discipline now maps the prototype to its upstream and
  downstream workflow skills — `/planning:prd`, `/improve-architecture:improve-architecture`,
  `/planning:architect`, and `/implementation:implement` — each invoked only when the sibling
  plugin is installed.
- **Named handoff capability in the auto-invoke gate.** The gate's "checkpointing your current
  work first" now names `/session-flow:handoff` (when installed) as the checkpoint capability.
