---
section: failure-taxonomy
dispatch_ref: "lead-(e); original-dispatch-(f)"
question: "Enumerate the failure taxonomy with exact error strings, so X errors can be classified rather than guessed."
verdict: only-2-of-12-classes-are-cookie-remediable; none-of-the-3-observed-errors-is-auth
confidence: high
evidence_tier: verified-firsthand (all 3 observed strings reproduced) + source
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# Failure taxonomy

## The routing answer the design needs

**None of the three dispatch-observed errors is a bot-challenge or auth failure.** Only classes
**6 and 7** below are cookie-remediable, and both arrive via `raise_login_required`. Routing the
observed errors into a YouTube-shaped bot-challenge cookie-fallback path would retry with cookies
pointlessly and misclassify a structural "no video here" as an auth problem.

> **Gate the cookie fallback on `raise_login_required`-shaped errors only.**

## Full taxonomy

| # | Emitted by | Exact string | Trigger | Class |
|---|---|---|---|---|
| 1 | extractor L1377 | `No video could be found in this tweet` | zero entries **and** no usable outbound link | terminal — post genuinely has no video |
| 2 | L1380 → core | `Unsupported URL: <external>` | zero entries; `entities.urls[0].expanded_url` present and ≠ url → `url_result` chases **off-platform** | mis-route — not an X failure |
| 2b | core | `Unsupported URL: <x.com/...>` | URL never matched `_VALID_URL` at all | caller bug — **same string, unrelated cause** |
| 3 | core `YoutubeDL.py:1195` | `No video formats found!` | an entry reached processing with **empty `formats`** | media claimed, formats unresolved |
| 4 | L1086 | `Twitter API says: <cause>` | `tombstone` in result (deleted / withheld / age-gated) | terminal |
| 5 | L1093 | `<reason>` or `Requested tweet is unavailable` | `typename == 'TweetUnavailable'` | terminal |
| 6 | L1090 / L1092 | `NSFW tweet requires authentication` / `You are not authorized to view this protected tweet` | `raise_login_required` | **COOKIE-REMEDIABLE** |
| 7 | L141 | server-supplied text containing `not authorized` | `raise_login_required` | **COOKIE-REMEDIABLE** |
| 8 | L143 | `Error(s) while querying API: <msg>` | GraphQL `errors` array | usually transient or breakage |
| 9 | L110 | `Could not retrieve guest token` | guest-token fetch returned nothing | ~unreachable (a 429 raises inside `_download_json` first); zero user reports |
| 10 | L1171 | `Syndication endpoint returned empty JSON response` | syndication fallback returned empty | terminal |
| 11 | L1184 | `'<x>' is not a valid API selection` | bad `twitter:api` extractor-arg | caller bug |
| 12 | L1357 / L1359 | `Video #N is unavailable` / `Media #N is not a video` | `/video/N` index out of range or non-video | caller bug |

Note `raise_no_formats(msg, expected=True)` (`common.py:1265`) *raises* unless
`--ignore-no-formats-error` or `--wait-for-video` is set, in which case it downgrades to a warning
and the extractor returns a format-less `info` dict.

## All three observed strings REPRODUCED FIRSTHAND on 2026.07.04

**#1 — `No video could be found in this tweet`**

```
$ yt-dlp -J https://twitter.com/jack/status/20
ERROR: [twitter] 20: No video could be found in this tweet
```
Also reproduced on current posts: `animeupdates/2087413720573989343`,
`Qatar_Tribune/2079491429148021236`.

**#2 — `Unsupported URL: <external site>` (the off-platform chase)**

```
$ yt-dlp -J https://twitter.com/GoogleDoodles/status/1779857206218756571
ERROR: Unsupported URL: https://doodles.google/doodle/celebrating-etel-adnan/

$ yt-dlp --list-subs https://x.com/gmail/status/2079628406803825062
ERROR: Unsupported URL: https://support.google.com/mail/answer/19870
```

**#3 — `No video formats found!` — trigger IDENTIFIED**

```
$ yt-dlp --list-subs https://x.com/AndroidAuth/status/2079509697896280418
ERROR: [twitter] 2079509697896280418: No video formats found!; please report this issue on ...
$ yt-dlp -v ... | grep "Extracting from"
[debug] [twitter] Extracting from summary_large_image card info: https://t.co/BFlalG5KG8
```

The card name `summary_large_image` is **not** in the handled set (`player`, `periscope_broadcast`,
`broadcast`, `audiospace`, `summary`, `unified_card`), so it falls into the vmap `else` branch
(L1321). There `get_binding_value('player_stream_url')` returns `None`, and
`_extract_formats_from_vmap_url(None, ...)` returns `([], {})` — **fabricating a single
empty-format entry**. Because `entries` is then non-empty, the `if not entries:` link-chase branch
at L1374 is skipped.

> **A plain link post with a large-image preview therefore yields `No video formats found!` rather
> than `No video could be found in this tweet`.** This is effectively a card-classification bug in
> the extractor: two semantically identical posts (text + link, no video) produce two different
> errors depending only on the preview card type.

## Class #2 is the dangerous one for a digest

- **DOCUMENTED, known and unfixed:** issue **#9715**, "Twitter/X: Unpredictable behaviour following
  links in Tweets" — open since **2024-04-18** (~848 days), labeled `site-bug`, `patch-available`.
  Also **#16585** (CNN, circular redirection, open since 2026-04-27).
- **The error case is the safe case.** When the linked site **is** supported, yt-dlp does not error
  — it returns the **off-platform video's** content via
  `url_result(expanded_url, display_id=twid, **info)`, merged with the tweet's metadata. #9715
  documents exactly this: a tweet linking to YouTube yields the YouTube video's info dict.

> **A digest would silently ingest a YouTube (or arbitrary site's) video as if it were the X post.**
> This is a correctness hazard far worse than a hard error.
>
> **Mitigation:** reject any result whose `extractor` field is not `twitter`. Verified that the
> field is present and correct on real output (`"extractor": "twitter"`).

## Classification guidance

- **Cookie-fallback eligible:** #6, #7 only.
- **Terminal, do not retry:** #1, #4, #5, #10.
- **Reject-and-flag (wrong content risk):** #2 — and, more importantly, the *silent* success form of
  the same code path.
- **Caller bug, fix the invocation:** #2b, #11, #12.
- **Transient / breakage, retry or alert:** #8; also the 429 path, which does **not** error but
  warns `Rate-limit exceeded; falling back to syndication endpoint`.
- **Ambiguous:** #3 covers both "extractor mis-classified a non-video card" (the
  `summary_large_image` case, benign — the post has no video) and "real media whose formats failed
  to resolve" (a genuine failure). These are **not distinguishable from the error string alone**;
  the debug line `Extracting from <card_name> card info` disambiguates.
