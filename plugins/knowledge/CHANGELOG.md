# Changelog

All notable changes to the `knowledge` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## 0.4.0

### Changed

- **`youtube` skill now honors the `library_dir` seam.** The invoking skill wires a
  non-default `library_dir` into the extraction pipeline by passing
  `run.mjs --work-root <dir>`, which the launcher translates into the
  `YOUTUBE_WORK_ROOT` environment variable the scripts already read — so watch,
  transcript, and queue artifacts land under the configured directory instead of
  always at the consuming repo root. Agent-written slice artifacts (the queue table,
  its claim stubs, and every Output-contract deliverable) anchor to the same resolved
  root, so a non-default `library_dir` never splits a slice across two directories. The default (`.`) path is unchanged: no flag,
  `resolveWorkRoot()` keeps its `CLAUDE_PROJECT_DIR` → `process.cwd()` fallback. A
  double-quoted CLI arg was chosen over an inline `YOUTUBE_WORK_ROOT=… node` prefix
  because the latter is bash-only and fails under PowerShell.
- **`setup` Output** now states that `library_dir` governs where youtube artifacts
  land, restoring the stronger wording softened while the seam was unwired
  (`book-distill` remains the documented exception).

## 0.2.0

### Added

- **`youtube` skill** (`/knowledge:youtube`) — watch a single public YouTube video
  (transcript + visual frames), harvest reference links, drive external research,
  and synthesize a prioritized repo-applicability menu. Actions: `watch`, `queue`,
  `transcript`, `resume`.
- Bundled `extraction/` node pipeline for the youtube skill. Its dependencies are
  installed into `${CLAUDE_PLUGIN_DATA}` on first use via
  `skills/youtube/extraction/setup-deps.mjs` (idempotent; re-run after a plugin
  update). Media binaries (`yt-dlp`, `ffmpeg`, ImageMagick) remain OS-level installs
  the skill's Prerequisites section documents.

### Notes

- The youtube pipeline is ESM. Its entry points run through
  `skills/youtube/extraction/run.mjs`, which injects an ESM resolve hook so bundled
  dependencies resolve from `${CLAUDE_PLUGIN_DATA}` (NODE_PATH is CommonJS-only and
  does not apply).

## 0.1.1

- Prior baseline: `book-distill` and `setup` skills.
