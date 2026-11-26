---
bump: minor
---

### Added

- `plugins/disk-hygiene/lib/install_authority.py` owning explicit-input install-layout derivation, trusted OS-account config-dir lookup, and launch disclosure with zero ambient `sys.argv` or environment trust.
- `plugins/disk-hygiene/lib/data_root_state.py` owning `DataRoot`, `CleanRunStore`, the complete 6-directory `ENGINE_OWNED_DIRS` set, strict ASCII `sanitize_session_id`, and cross-language parity tests against `hooks.json`, `resume-notice.mjs`, and `run-python-hook.sh`.
- `plugins/disk-hygiene/lib/policy_cascade.py` owning `@functools.lru_cache` immutable `BaselineSnapshot`, `snapshot_protected_exact_names`, ADR 0075 standing policy cascade, and YAML/JSON overlay validation.
- `killswitch_config.probe_effective` sharing managed-over-user, `managed-settings.d/*.json`, and Linux root-ownership trust precedence with `resolve_effective`.

### Changed

- Rewired `engine_context.py` and `kill_switch_probe.py` to consume `lib/install_authority.py` and `killswitch_config.probe_effective` directly with zero `destructive_guard` imports.
- Rewired `policy_migration.py` to consume `lib/policy_cascade.py` and `lib/yaml_subset.py` directly with zero `hygiene` imports.
- Cached `system_roots()` and pre-casefolded `exact_names` across `hygiene.py` scan and revalidation hot loops, and pre-indexed snapshot descendants (`O(N log N)`) in `investigated_catalog.py`.

### Fixed

- Added `clean-invoked` and `guard-no-interpreter` to `ENGINE_OWNED_DIRS` and aligned Python session-ID sanitization to strict ASCII (`[^A-Za-z0-9_-]`) matching Bash and Node hooks.
- Fixed `apply_plan` inner per-entry revalidation dropping `snapshot["policy"]["protected_exact_names"]` and re-reading `baseline-policy.json` from disk on every entry.
- Fixed `kill_switch_probe.py` missing managed-settings overrides and install-scoped `plugin_id` narrowing.
