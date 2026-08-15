# Source: YouTube

Read when the URL is a `youtube.com` / `youtu.be` video. Everything here is YouTube-specific;
the shared pipeline lives in the hub and `../../context/watch-pipeline.md`.

## Accepted URLs and slice key

| Shape | Example |
| --- | --- |
| Watch page | `https://www.youtube.com/watch?v=<id>` |
| Short link | `https://youtu.be/<id>` |
| Shorts / embed / live | `https://www.youtube.com/{shorts,embed,live}/<id>` |

Slice key = the 11-character video id, derived from the URL rather than from post-redirect
metadata. One id → one slice; the id is also the `QUEUE.md` dedupe key.

<!-- RECONCILE: Phase 1 moves id extraction from `acquisition/acquire.js` behind the YouTube
adapter's `matchUrl` / `extractSliceKey`, and moves the whole preflight acceptance pattern set
from `preflight-metadata.js` behind `acceptForEnqueue`. Confirm the accepted-shape list above
against the landed adapter, including subdomain handling. -->

## Acquisition

Captions (transcript action and the caption leg of watch) use:

```text
--write-subs --write-auto-subs --sub-langs "en.*,-live_chat" --sub-format vtt
```

Built by `acquisition/build-yt-dlp-args.js`. Auto-generated captions are in scope for YouTube —
the caption ladder below deliberately falls through to them.

**Caption ladder** — manual EN → auto EN → auto-translate EN → STOP and surface if exhausted.
Rung 3 and below trigger the auto-caption dedup clean-up pass. Declared caption class:
platform-manual-preferred.

**Comments and extractor args** are YouTube capabilities, not pipeline defaults: comment harvest
is on (the pinned comment feeds link harvest) with
`youtube:max_comments=20,all,top;comment_sort=top`.

<!-- RECONCILE: Phase 1 makes both `--write-comments` and `--extractor-args`
adapter-declared rather than unconditionally pushed at `build-yt-dlp-args.js:113-115`. Confirm the
declared `extractorArgs` string and `comments` capability against the landed YouTube adapter. -->

## Auth and throttle overrides

Four personal `userConfig` options tune YouTube acquisition. Each is wired the **same**
cross-platform way as `--work-root` (see `../../context/output-contract.md`) — a leading, double-quoted
flag on the `run.mjs` invocation that the launcher forwards to the extraction child as an
environment variable. Those env vars are internal plumbing, not a channel to set by hand.

Apply the **same guard** as `library_dir`: pass a flag only when its option holds a non-empty
value other than the option default, and not still an unexpanded `${user_config.…}` token;
otherwise omit it and the pipeline keeps its built-in default. All are leading and
order-independent, so they combine with `--work-root` in any order.

| Option | Flag | Pass when | Effect |
|---|---|---|---|
| `${user_config.yt_dlp_js_runtimes}` | `--js-runtimes "<value>"` | set and not the default `node` | `off` omits yt-dlp's `--js-runtimes`; any other value selects that runtime |
| `${user_config.yt_dlp_cookies_file}` | `--cookies-file "<value>"` | non-empty | authenticated acquisition from a Netscape cookies.txt (never commit it) |
| `${user_config.yt_dlp_cookies_from_browser}` | `--cookies-from-browser "<value>"` | non-empty | forces one browser's cookies instead of the automatic platform-ordered fallback; a cookies file wins over it |
| `${user_config.max_concurrent_acquires}` | `--max-concurrent-acquires "<value>"` | set and not the default `1` | caps concurrent acquisitions (1–3); higher increases HTTP 429 risk |

Example combining a non-default library dir with a forced cookie source (unset options
contribute no flag):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" \
  --work-root "${CLAUDE_PROJECT_DIR}/${user_config.library_dir}" \
  --cookies-from-browser "${user_config.yt_dlp_cookies_from_browser}" \
  <script.js> [args…]
```

**Browser-cookie-profile fallback is a YouTube capability.** When a bot/sign-in challenge is
classified, acquisition iterates browser cookie profiles before giving up. Recovery detail:
`../../context/gotchas.md`.

## Failure patterns

| Pattern | Class | Response |
| --- | --- | --- |
| Bot / sign-in challenge ("Sign in to confirm you're not a bot") | login-required | cookie fallback: cookies file, then browser profiles |
| HTTP 429 | retryable | backoff + honor the concurrency cap; see `../../context/gotchas.md` |
| Removed / private / 404 at preflight | fatal | `reject` / `unavailable` — never enqueued |
| Not a YouTube video URL | fatal | `reject` / `invalid-url` |

<!-- RECONCILE: Phase 1 sources these from the adapter's `errorPatterns` table, seeded from
`YOUTUBE_BOT_CHALLENGE_PATTERNS` (`acquire-yt-dlp-auth.js:8`), and consumed by the classification
predicates in `spawn-yt-dlp-with-auth-fallback.js`. Confirm the four rows map onto the landed
four-type taxonomy (retryable / fatal / login-required, plus dispatch-level unsupported-source),
and that cookie fallback fires on login-required classification only. -->

## Prerequisite floor

yt-dlp **2026.6** or newer, for every action. `--js-runtimes node` by default; set the
`yt_dlp_js_runtimes` option to `off` to omit it. Install commands are in the hub's
Prerequisites section.
