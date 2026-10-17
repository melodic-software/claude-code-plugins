---
bump: patch
---

### Fixed

- `video-digest` now runs its readiness check as one plain command, `extraction/preflight.mjs`, pre-approved in `allowed-tools`, so worktree-isolated auto-mode sessions no longer refuse the compound preflight block. It probes the node dependencies, yt-dlp, ffmpeg, ImageMagick and faster-whisper, prints where the dependencies install and how to relocate them with `--data-dir`, and always exits 0. Prerequisites tells the model to run it by hand when the pre-computed context did not run.
- `video-digest` renders each `userConfig` option once in a SKILL.md "Configured options" table, and the output-contract and source spokes refer to it, so a configured `library_dir`, cookies file, JS runtime or concurrency cap reaches the pipeline instead of arriving as an unsubstituted token.
- `video-digest`'s Bootstrap gate now stops when the node dependencies are missing or `setup-deps.mjs` fails, and states that a hand-run of yt-dlp, ffmpeg or ImageMagick is not the skill's output.
