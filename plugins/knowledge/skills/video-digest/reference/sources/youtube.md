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

Slice key = the 11-character video id (`[A-Za-z0-9_-]{11}`), derived from the URL rather than from
post-redirect metadata; metadata `id` is a fallback only when the URL yields none. One id → one
slice; the id is also the `QUEUE.md` dedupe key. Canonicalization is identity: every claimed
variant is acquired verbatim.

## Acquisition

Captions (transcript action and the caption leg of watch) use:

```text
--write-subs --write-auto-subs --sub-langs "en-orig,en.*,-live_chat" --sub-format vtt
```

Built by `acquisition/build-yt-dlp-args.js`. Auto-generated captions are in scope for YouTube, and
the caption ladder below deliberately falls through to them.

**Caption ladder:** manual EN → auto EN (the original `en-orig` before a bare auto `en`) →
auto-translate EN → STOP and surface if exhausted. A track is manual only when info.json
`subtitles` lists its key.
Rung 3 and below trigger the auto-caption dedup clean-up pass. Declared caption class:
`manual-and-auto`. Declared transcript strategy: `captions`.

This spoke's decision: a caption file counts as manual only when info.json `subtitles` lists its
language key; otherwise a bare `.en.vtt` is auto, and `.en-orig.vtt` wins over it when both exist. The observed translated bare
track behind the decision is [#6740](https://github.com/melodic-software/claude-code-plugins/issues/6740).

- **Pointer**: when caption files or info.json caption keys look different, fetch the probe in
  [#6740](https://github.com/melodic-software/claude-code-plugins/issues/6740) and yt-dlp's subtitle
  options at <https://github.com/yt-dlp/yt-dlp#subtitle-options> live.
- **As of**: 2026-10-10
- **Recheck trigger**: a yt-dlp release note that renames subtitle output files or changes the
  `subtitles` / `automatic_captions` keys in info.json.

**Comments and extractor args** are adapter-declared capabilities, not pipeline defaults. Both
flags are pushed only because this adapter declares them. Comment harvest is on (the pinned
comment feeds link harvest) with `--extractor-args youtube:max_comments=20,all,top;comment_sort=top;skip=translated_subs`.

This spoke's decision: the first caption pass requests no translations of manual tracks (`en-de`,
`en-en`), so a throttled translation cannot fail the pass, and the captions-only retry after an
empty ladder requests them again so auto-translate EN stays reachable. `skip=translated_subs` is
the extractor argument that carries the decision.

- **Pointer**: when a translated track lands despite the skip, or the retry finds none, fetch
  yt-dlp's YouTube extractor arguments at <https://github.com/yt-dlp/yt-dlp#youtube> live.
- **As of**: 2026-10-10
- **Recheck trigger**: a yt-dlp release note that renames or changes `skip` values for the youtube
  extractor.

A caption pass that exits non-zero still selects from the tracks already written, and the failed
track's `ERROR:` line lands in `transcriptDegradation`.
No extractor allow-list is declared: the youtube extractor resolves claimed URLs in-family, with
no foreign delegation on the single-video path.

## Auth and throttle overrides

Four personal `userConfig` options tune YouTube acquisition. Each is wired the **same**
cross-platform way as `--work-root` (see `../../context/output-contract.md`): a leading, double-quoted
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

One more throttle flag has no `userConfig` option: `--acquire-phase-gap <sec>`, a leading
`run.mjs` flag. A `watch` acquires in two passes, the video and then the captions, and the flag sets
the pause between them (default 3 seconds; the flag needs a value, and a non-numeric or negative
one keeps the default). Raise it after an HTTP 429 on the caption pass, for example `--acquire-phase-gap 10`; the
launcher forwards it as `VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC`. Pass it only when you want a gap other
than the default.

Example combining a non-default library dir with a forced cookie source (unset options
contribute no flag):

```bash
node "<skill-dir>/extraction/run.mjs" --data-dir "<plugin-data>" \
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
| Removed / private / 404 at preflight | fatal | adapter | `reject` / `unavailable`, never enqueued |
| Not a YouTube video URL | queue-lane rejection (not an error class) | adapter (`acceptForEnqueue`) | `reject` / `invalid-url` |
| Unsupported host | unsupported-source | registry, before any adapter | `reject` / `invalid-url`, listing the supported sources |
| HTTP 403 on media fragments | stale client | this spoke | update yt-dlp first |
| HTTP 429 / 503 / connection reset / timeout | retryable | **shared retry policy**, not this adapter | backoff + honor the concurrency cap; see `../../context/gotchas.md` |

The HTTP 403 row is this spoke's decision: treat a media-fragment 403 as a stale client and update yt-dlp before any other recovery. The probe that an aging client failed that way and a newer build succeeded is [#6048](https://github.com/melodic-software/claude-code-plugins/issues/6048).

- **Pointer**: when a media download returns HTTP 403, fetch the probe in [#6048](https://github.com/melodic-software/claude-code-plugins/issues/6048) and the current yt-dlp release at <https://github.com/yt-dlp/yt-dlp/releases> live.
- **As of**: 2026-10-03
- **Recheck trigger**: a yt-dlp release note that changes how an aging binary fails a media download.

The last row is the one to read carefully: this adapter declares **no** retryable patterns of its
own. Transport-level retry is shared machinery applied to every source, so a 429 never reaches
adapter classification. Cookie fallback fires on a login-required classification only, and only
because this adapter declares the browser-cookie-fallback capability. An explicit cookies-file or
cookies-from-browser setting suppresses the profile loop entirely.

## Prerequisite floor

yt-dlp **2026.6** or newer, for every action. `--js-runtimes node` by default; set the
`yt_dlp_js_runtimes` option to `off` to omit it. Install commands are in the hub's
Prerequisites section.
