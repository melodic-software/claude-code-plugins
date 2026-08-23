# Changelog

All notable changes to the `kindle-dedrm` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.3]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.7.2]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.7.1]

### Changed

- **`/kindle-dedrm:manage`'s trigger phrases are now single-quoted.** All eight
  (`'set up Kindle DRM removal'`, `'remove DRM from Kindle books'`,
  `'extract keys from my Kindle library'`, `'sync new Kindle books I bought'`,
  `'check if DeDRM setup is current'`, `'clean up Kindle DRM tools'`, `'undo DeDRM setup'`,
  `'convert Kindle books to EPUB'`) were written with escaped double quotes, which the skill-quality
  gate's trigger-drop protection does not track — so none of them carried regression cover. Quoting
  only; the wording is unchanged.

  `'set up Kindle DRM removal'` is deliberately kept here even though the sibling
  `/kindle-dedrm:setup` also lists it. That looks like a routing ambiguity, but `setup` is
  `disable-model-invocation: true` — its description is never matched against user text — so
  `manage` is the only skill that can receive the phrase by model invocation, and its action router
  delegates to `/kindle-dedrm:setup` from there. Dropping the duplicate would make the phrase
  reachable only by an explicit slash command.

## [0.7.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.4]

### Fixed

- **The pre-flight rule for a non-2.8.0 Kindle install no longer gives a self-contradictory reason.**
  "that's destructive and reversible damage" argued against its own warning; it now reads
  "destructive and costly to reverse (a full re-download/re-sync of the library), so it stays
  user-driven", naming the actual cost the manual-uninstall rule guards against.

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
