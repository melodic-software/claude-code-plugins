# Changelog

All notable changes to the `playwright` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Added

- `reference/tracing-and-video.md` gains a **Frame size — two levers, not one**
  section documenting `playwright-cli video-start --size "<W>x<H>"`, which the
  skill had never mentioned. Video frame size is derived from the viewport at
  browser-context creation and fitted into an 800×800 box, so the previously
  canonical bare `video-start demo.webm` recorded at 800×450 regardless of
  viewport intent, and `resize` afterwards did not change it. A correct
  recording needs two matched levers — `PLAYWRIGHT_MCP_VIEWPORT_SIZE` prefixed
  on `open` for what the page renders at, and `--size` for the output frame —
  and the section tabulates the measured outcome of each partial combination.
  Also notes that the config file's `saveVideo` block is whole-session
  auto-save, a different mechanism from on-demand `video-start`.

### Changed

- The canonical video example now carries both size levers, with a neutral
  illustrative resolution, and the capture checklist points at the new section.
- `SKILL.md`'s "Defaults (accept, don't override)" section gains an explicit
  video-recording exception. The `1280×720` viewport row stays — it is the
  correct CLI default — and so does the "don't put `PLAYWRIGHT_MCP_*` in
  project settings" posture; what was missing was the documented carve-out that
  video needs a per-command viewport prefix on `open`. Skill frontmatter is
  untouched.

### Fixed

- "Known costs" no longer claims "1280×720 WebM is ~5 MB/minute". The CLI never
  emits 1280×720 by default, and the figure was unsourced — it appears in no
  upstream or official Playwright documentation. Replaced with a qualitative
  statement that size scales with frame area and on-screen motion, rather than
  re-anchoring an invented number to a different resolution.

## [0.4.0]

### Added

- Synced vendored upstream baseline from `@playwright/cli@0.1.13` to `0.1.17`
  and folded the genuine new commands/flags into the distilled reference
  files: `find` (context-search a snapshot without capturing it all),
  `--hires` screenshots, `--mobile`/`--device=` emulation, and Windows
  `&`-in-URL shell-escaping guidance, all in `reference/commands.md`;
  `video-show-actions`/`video-hide-actions` auto-annotated video overlays in
  `reference/tracing-and-video.md`; and a distilled summary of the (now-merged)
  spec-driven plan/generate/heal workflow in `reference/test-generation.md` —
  self-contained rather than pointing normal use at `vendor/`, which this
  skill's own SKILL.md reserves for drift-detection reading only.

## [0.3.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. The vendored Apache-2.0 upstream license reference (shipped
  in-plugin) is unchanged. No behavior change.

## [0.3.1]

### Changed

- Artifact-naming example in the tracing/video reference drops the tracker-shaped
  `issue-123` filename token and the hardcoded `docs/evidence/` directory for
  agnostic `<artifact-dir>/<descriptive-name>` placeholders, so the destination
  comes from the consumer's own project conventions rather than presuming
  GitHub-integer issue numbering and a mandated evidence-directory layout.

## [0.3.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/playwright:setup check` reads
  the main skill and its `reference/` files as the single source of truth and probes the
  `playwright-cli` binary and browser resolvability (surfacing the `install-browser` step and
  sandbox-egress caveat from the plugin's own docs). `apply` is guidance-and-verify with
  exactly one write path — the explicitly invoked `apply install-cli`, which runs the global
  `npm install -g @playwright/cli` (stated before running) and re-probes the binary
  afterward. It points at `/playwright:playwright update` for the vendored-baseline flow
  rather than wrapping it.

## [0.2.1]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/playwright/` for earlier changes.
