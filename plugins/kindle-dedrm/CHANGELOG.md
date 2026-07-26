# Changelog

All notable changes to the `kindle-dedrm` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.3]

### Changed

- **`status.sh`/`sync-finalize.sh` annotated for the shell-portability-lint
  gate's newly-active `stat -c` class (#1510).** Both scripts' cached-installer
  size probe (`stat -c%s ... || echo <default>`) has no BSD `stat -f`
  fallback, which the gate would otherwise flag as a real gap — but this
  plugin's scripts are Windows-only (Git Bash + PowerShell + the
  `LOCALAPPDATA`/`USERPROFILE`/`APPDATA` env vars they already depend on), so
  a BSD fallback would be dead code. Each site now carries a `portability-ok:`
  annotation recording that. No behavior change.

## [0.6.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.1]

### Changed

- **DeDRM_tools pin re-pinned `v10.0.20` → `v10.0.28`** (maintainer re-pin;
  upstream drift confirmed live 2026-07-19). New asset SHA256
  `520cce70…c362947` (1,944,296 bytes, asset date 2026-07-14), fetched and
  hash-verified; the prior pin is recorded for rollback. A full single-book
  extraction was NOT re-run (manual, machine-bound) — the only consumed file,
  `DeDRM_plugin.zip`, is present; the v10.0.28 additions (Frida/MSIX decrypt
  tools) target the newer MSIX Kindle app and are not used by this skill.
- **Tutorial URL repointed + drift probe reworked.** The primary tutorial moved
  from `remove-drm-from-kindle-ebooks/` (now HTTP 404) to
  `drm-removal-from-kindle-ebook-purchases-old-method/` and is now
  subscriber-gated, so the `update` action can no longer walk its body for the
  current Key_Finder zip URL. `check-drift.sh` now HEAD-probes the pinned direct
  Key_Finder zip URL as the authoritative signal (still serving the
  byte-identical zip, SHA-verified 2026-07-19); roll-forward auto-discovery is a
  documented capability loss until a subscriber re-confirms new builds by hand.

### Deferred

- **Obsolescence watch:** upstream relabeled the entire Kindle-for-PC + KFX
  approach the "OLD Method" and is pushing an MSIX-app successor
  (`msix-amazon-kindle-reading-app-dedrm/`). Trigger to migrate: the pinned
  Kindle-for-PC 2.8.0 installer URL or the Key_Finder zip going non-200. Sources
  retained in `references/sources.md`.

## [0.6.0]

### Changed

- **BREAKING: router skill `kindle-dedrm` renamed to `manage`** (fleet conformance wave —
  naming grammar, verb-first skill names). The router now invokes as `/kindle-dedrm:manage` (was
  `/kindle-dedrm:kindle-dedrm`); the `setup` skill is unchanged. Update any saved
  invocations. Skill behavior, actions, scripts, and evals are unchanged; only the leaf
  name, its namespace token, and the internal skill path changed.

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
