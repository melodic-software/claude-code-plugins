# Source: YouTube

Read when the URL is a `youtube.com` / `youtu.be` video. Everything here is YouTube-specific;
the shared pipeline lives in the hub and `../../context/watch-pipeline.md`.

## Accepted URLs and slice key

| Shape | Example |
| --- | --- |
| Watch page | `https://www.youtube.com/watch?v=<id>` |
| Short link | `https://youtu.be/<id>` |
| Path-prefixed | `https://www.youtube.com/{shorts,embed,live,v}/<id>` |

Owned hosts are `youtube.com` and `youtu.be`. Host matching is suffix-aware, so `www.`, `m.`, and
`music.` subdomains all resolve here, while lookalikes (`notyoutube.com`,
`youtube.com.evil.example`) do not.

Slice key = the 11-character video id (`[\w-]{11}`), derived from the URL rather than from
post-redirect metadata; metadata `id` is a fallback only when the URL yields none. One id → one
slice; the id is also the `QUEUE.md` dedupe key. Canonicalization is identity — every claimed
variant is acquired verbatim.

## Acquisition

Captions (transcript action and the caption leg of watch) use:

```text
--write-subs --write-auto-subs --sub-langs "en.*,-live_chat" --sub-format vtt
```

Built by `acquisition/build-yt-dlp-args.js`. Auto-generated captions are in scope for YouTube —
the caption ladder below deliberately falls through to them.

**Caption ladder** — manual EN → auto EN → auto-translate EN → STOP and surface if exhausted.
Rung 3 and below trigger the auto-caption dedup clean-up pass. Declared caption class:
`manual-and-auto`. Declared transcript strategy: `captions`.

**Comments and extractor args** are adapter-declared capabilities, not pipeline defaults — both
flags are pushed only because this adapter declares them. Comment harvest is on (the pinned
comment feeds link harvest) with `--extractor-args youtube:max_comments=20,all,top;comment_sort=top`.
No extractor allow-list is declared: the youtube extractor resolves claimed URLs in-family, with
no foreign delegation on the single-video path.

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
node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" \
  --work-root "${CLAUDE_PROJECT_DIR}/${user_config.library_dir}" \
  --cookies-from-browser "${user_config.yt_dlp_cookies_from_browser}" \
  <script.js> [args…]
```

**Browser-cookie-profile fallback is a YouTube capability.** When a bot/sign-in challenge is
classified, acquisition iterates browser cookie profiles before giving up. Recovery detail:
`../../context/gotchas.md`.

## Failure patterns

| Pattern | Class | Declared by | Response |
| --- | --- | --- | --- |
| Bot / sign-in challenge ("Sign in to confirm you're not a bot") | login-required | adapter | cookie fallback: cookies file, then browser profiles |
| Removed / private / 404 at preflight | fatal | adapter | `reject` / `unavailable` — never enqueued |
| Not a YouTube video URL | queue-lane rejection (not an error class) | adapter (`acceptForEnqueue`) | `reject` / `invalid-url` |
| Unsupported host | unsupported-source | registry, before any adapter | `reject` / `invalid-url`, listing the supported sources |
| HTTP 429 / 503 / connection reset / timeout | retryable | **shared retry policy**, not this adapter | backoff + honor the concurrency cap; see `../../context/gotchas.md` |

The last row is the one to read carefully: this adapter declares **no** retryable patterns of its
own. Transport-level retry is shared machinery applied to every source, so a 429 never reaches
adapter classification. Cookie fallback fires on a login-required classification only, and only
because this adapter declares the browser-cookie-fallback capability — an explicit cookies-file or
cookies-from-browser setting suppresses the profile loop entirely.

## Prerequisite floor

yt-dlp **2026.6** or newer, for every action. `--js-runtimes node` by default; set the
`yt_dlp_js_runtimes` option to `off` to omit it. Install commands are in the hub's
Prerequisites section.
