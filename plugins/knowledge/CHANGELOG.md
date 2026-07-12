# Changelog

All notable changes to the `knowledge` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

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
