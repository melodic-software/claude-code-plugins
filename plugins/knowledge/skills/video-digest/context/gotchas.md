# Video digest gotchas

Observed failure modes and their recovery behavior. Terse operational directives live at their decision points in `SKILL.md`; this file explains the *why*.

## YouTube bot / sign-in check

Acquisition tries without cookies first; on *"Sign in to confirm you're not a bot"* it auto-retries with `--cookies-from-browser` using installed browsers (platform order: Edge/Chrome on Windows). No configuration required when you are signed into YouTube in a local browser. Optional overrides via the plugin's personal `userConfig`: the `yt_dlp_cookies_from_browser` option (force one browser) or the `yt_dlp_cookies_file` option (Netscape cookies.txt path). Never commit cookie files.

## HTTP 429 throttling

Acquisition applies yt-dlp `--retries`, `--sleep-requests`, `--sleep-subtitles` plus an **outer exponential backoff on HTTP 429**. Batch runs cap concurrency via the `max_concurrent_acquires` option (default 1, max 3); raising it increases 429 risk.

A caption download still throttled after that backoff fails the run with a rate-limit error naming the yt-dlp message, not "No English captions found": the captions may exist. Wait several minutes and re-run. When another track already landed a usable English caption, the run continues on it and records the failed track's `ERROR:` line in `transcriptDegradation`.

## Temp-session expiry

Bulk frames and contact sheets stay in OS `tempSession` dirs, not the repo. When those dirs have been reaped, `run-state/watch.json` `tempSession` paths are stale, so **re-run `run-watch.js`** before vision (resume detects this and stops for the same reason).

A successful `close` removes those recorded dirs on purpose, after it marks the slice complete. When one is locked (on Windows, a scanner or player holding a file open), `close` warns on stderr with the path and still succeeds; delete that dir by hand once the lock is gone.

## Cloud agent without media toolchain

`watch` needs ffmpeg + ImageMagick for frame extraction and contact sheets. A cloud agent lacking the media toolchain must **fail closed and not run watch**; route to the prerequisites fix path instead of producing a frameless run. The tools can often be installed in place: `SKILL.md` "Prerequisites" lists the fallbacks to try when the platform package is missing or below its floor.

## Video download blocked (HTTP 403 on the media stream)

Captions and metadata can come through while the video itself is refused: yt-dlp fetches the caption track and then fails the media download with HTTP 403. YouTube applies this most to requests from datacenter IP ranges, so a cloud container sees it where a home connection does not. The full acquisition runs the video pass first, so `run-watch.js` exits non-zero before any slice is written, and the watch stops there ("No video, no watch" in `SKILL.md`). The fix path is to run the watch from a machine whose connection YouTube serves, such as a local session. Cookies (the `yt_dlp_cookies_file` option) and a proof-of-origin token provider plugin are the other levers; before reaching for either, read what each can and cannot clear and what it risks for the account in the yt-dlp [PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide), the [cookies FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp), and the [bgutil-ytdlp-pot-provider README](https://github.com/Brainicism/bgutil-ytdlp-pot-provider), as of 2026-10-06; recheck when a yt-dlp release changes which clients need a token or how cookies are passed.

## Phase state lives only in `watch.json`

`run-state/watch.json` holds the phase map and the `tempSession` paths, and it is the only phase-state file. A slice that carries a `watch-progress.json` is stale: read neither it nor into it, and never write one.
