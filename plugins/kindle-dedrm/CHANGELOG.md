# Changelog

All notable changes to the `kindle-dedrm` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Changed

- **`update` re-pins are checkout-gated** (fleet conformance wave, dim 15 —
  cache isolation). Applying an accepted drift recommendation now requires
  `${CLAUDE_PLUGIN_ROOT}` to be a git working tree; in installed form the
  skill stops after the drift report and routes the change to the plugin's
  source repository — bundled reference files are never edited in the
  read-only plugin cache.
- **Pins single-sourced**: `check-drift.sh` now parses every pin from
  `references/versions.md` (fail-hard on a pin it cannot read) instead of
  carrying a duplicate hardcoded copy that went stale after re-pins; the
  local-download verify also derives the installer filename from the pinned
  URL.

## [0.4.0]

### Added

- **Dedicated `/kindle-dedrm:setup` skill on the uniform check/apply contract**
  (`user-invocable: true`, `disable-model-invocation: true`). `check` probes
  prerequisites and current state read-only (Calibre, Python-not-WindowsApps-stub,
  pwsh, admin, Kindle version, firewall/ICACLS lock, downloads, plugins) via the
  plugin's own `status.sh`, reporting PASS/FAIL/INFO — a not-yet-provisioned
  machine is INFO, a wrong Kindle version or missing hard prerequisite is FAIL,
  and the extracted-key store is reported presence-only. `apply` runs the
  provisioning walkthrough by reference to `references/workflow.md`, with
  `apply download` as the explicit gated artifact-download subaction; the
  pinned-tag fallback and the Key_Finder URL empty-match guard stay authoritative
  in `references/workflow.md` (referenced, not restated).

### Changed

- **The router's `setup` action now delegates to `/kindle-dedrm:setup`.** The
  provisioning sequence has a single owner (`/kindle-dedrm:setup` →
  `references/workflow.md`); the router recommends it on a pristine machine
  instead of provisioning inline. `sync`, `update`, `cleanup`, and `status`
  are unchanged.

## [0.3.0]

### Changed

- **`gh` CLI declared and its absence handled** (prerequisite-visibility
  wave). The README Requirements now name the authenticated `gh` CLI; the
  setup workflow's DeDRM_tools download step falls back to the pinned tag from
  `references/versions.md` when `gh` is unavailable or returns nothing,
  instead of composing a malformed URL. The Key_Finder URL resolution gained
  the same empty-match guard (stop with the mirror-procedure pointer rather
  than feeding `curl` an empty URL).

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/kindle-dedrm/` for earlier changes.
