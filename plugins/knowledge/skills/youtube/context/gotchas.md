# YouTube skill — gotchas

Observed failure modes and their recovery behavior. Terse operational directives live at their decision points in `SKILL.md`; this file explains the *why*.

## YouTube bot / sign-in check

Acquisition tries without cookies first; on *"Sign in to confirm you're not a bot"* it auto-retries with `--cookies-from-browser` using installed browsers (platform order: Edge/Chrome on Windows). No env setup required when you are signed into YouTube in a local browser. Optional overrides: `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER` (force one browser) or `YOUTUBE_YT_DLP_COOKIES_FILE` (Netscape cookies.txt path). Never commit cookie files.

## HTTP 429 throttling

Acquisition applies yt-dlp `--retries`, `--sleep-requests`, `--sleep-subtitles` plus an **outer exponential backoff on HTTP 429**. Batch runs cap concurrency via `YOUTUBE_MAX_CONCURRENT_ACQUIRES` (default 1, max 3) — raising it increases 429 risk.

## Temp-session expiry

Bulk frames and contact sheets stay in OS `tempSession` dirs, not the repo. When those dirs have been reaped, `run-state/watch.json` `tempSession` paths are stale — **re-run `run-watch.js`** before vision (resume detects this and stops for the same reason).

## Cloud agent without media toolchain

`watch` needs ffmpeg + ImageMagick for frame extraction and contact sheets. A cloud agent lacking the media toolchain must **fail closed — do not run watch**; route to the prerequisites fix path instead of producing a frameless run.

## Retired `watch-progress.json`

`run-state/watch.json` (phase-map + `tempSession`) subsumes the old `watch-progress.json`, retired in Phase 4. Do not look for or write the old file — phase state lives only in `watch.json`.
