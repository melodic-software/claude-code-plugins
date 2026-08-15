# Source: X (Twitter)

Read when the URL is an `x.com` / `twitter.com` status. Everything here is X-specific; the shared
pipeline lives in the hub and `../../context/watch-pipeline.md`.

X differs from YouTube in three ways that change how you read a result: a status can carry **zero
or many** videos rather than exactly one, its captions are platform ASR rather than
author-authored, and its auth surface moves on a **weeks-to-months** cadence.

- [Accepted URLs and canonicalization](#accepted-urls-and-canonicalization)
- [Slice key and identity](#slice-key-and-identity)
- [Result arity — 0..N videos per post](#result-arity--0n-videos-per-post)
- [Provenance guard](#provenance-guard)
- [Captions and transcript strategy](#captions-and-transcript-strategy)
- [Failure patterns](#failure-patterns)
- [Rate-limit silent degradation](#rate-limit-silent-degradation)
- [Link harvest and reply chains](#link-harvest-and-reply-chains)
- [Auth and capabilities](#auth-and-capabilities)

## Accepted URLs and canonicalization

Status URLs on either host, with or without a pinned media index:

| Shape | Example |
| --- | --- |
| Status | `https://x.com/<user>/status/<status-id>` |
| Legacy host | `https://twitter.com/<user>/status/<status-id>` |
| Pinned media index | `https://x.com/<user>/status/<status-id>/video/2` |

Canonicalization re-derives the canonical status URL and happens **inside the source layer**, so
every entry path gets it by construction — `watch <url>`, `queue <url>` preflight, `watch <n>`
dequeue, `transcript <url>`, `resume`, and the recovery command emitted by
`detect-recoverable-bootstrap.js`. Do not canonicalize by hand at a call site.

A `/video/<n>` suffix is honored as a pinned index into the post's media, not as a separate slice.

## Slice key and identity

The slice key is the pair `(display_id, id)`:

- **`display_id` is the canonical identity** — the status id taken from the URL. Same status →
  same slice, no duplicates.
- **`id` rides along as the media discriminator**, distinguishing entries within one post.

A quote tweet or retweet can surface the *quoted* post's media under the outer status. The
snowflake timestamp embedded in the id (`(id >> 22) + 1288834974657`, ms since epoch) is compared
against the status timestamp; a large delta flags probable quote/retweet aliasing, and the flag is
recorded in slice metadata rather than silently resolved. On a link post the `id` may be the twid.

<!-- RECONCILE: Phase 2 implements the pair behind `extractSliceKey` with four identity fixtures
(original post, quote tweet, retweet, link post). Confirm the field names (`display_id` / `id`),
the aliasing-flag metadata key, and the snowflake epoch constant against the landed adapter. -->

## Result arity — 0..N videos per post

One status is **not** one video. Results are always a collection:

| Post shape | Result |
| --- | --- |
| Multi-video post | N entries |
| Single-video post | a one-entry collection — never a bare object |
| `/video/<n>` pinned | the honored index |
| No video, outbound link present | metadata-only 0-result; the blocked link is recorded in provenance and harvested links |
| No video, no link | metadata-only 0-result |

A 0-entry result is **well-formed**, not an error and not null. Both 0-cases produce a
**text-only digest with populated provenance** — post text, author, timestamps, harvested links —
and the watch pipeline's vision phases have nothing to absorb, so the digest rests on text and
research alone.

<!-- RECONCILE: Phase 1 defines the result envelope (0..N entries + shared metadata object, open
metadata namespace with reserved `source:`-prefixed keys, transcript as a replayable file path).
Confirm the envelope shape and the provenance field names before relying on this table. -->

## Provenance guard

Any acquisition result whose extractor is not `twitter` is a **blocked delegation** and is never
followed. X posts that link elsewhere would otherwise cause the downloader to chase the outbound
target and return someone else's media under this status's slice (yt-dlp upstream #9715).

The guard blocks the foreign media; it does **not** error the post. The status still resolves — as
a 0-video result — with the blocked link recorded.

## Captions and transcript strategy

X captions are **platform ASR**, so the transcript ladder differs from YouTube's:

- `--write-subs` only. **Never** `--write-auto-subs` — X has no author-authored caption tier for
  it to reach, and requesting it produces misleading rung classification.
- Subtitle keys arrive as raw `LANGUAGE` values (`en`, `en-US`, `en-GB`, `und`). Never index
  `subtitles['en']` directly; match across the observed key set.
- An `.en.vtt` from X is **not** a manual-EN rung. The shared caption ladder consumes the declared
  caption class so this does not misclassify as author-authored.

Strategy selection:

| Condition | Strategy |
| --- | --- |
| Captions present | `captions+repair` |
| Captions absent, ASR capability available | `asr` |
| Captions absent, ASR capability unavailable | explicit degradation — digest without transcript, stated in a named provenance field, never silent |

`captions+repair` runs proper-noun repair over the platform VTT, using the post text
(`description`) plus harvested links as the lexicon. The ASR rung is faster-whisper large-v3 at
`batch_size=8`, an optional closed-by-default capability delivered as a documented prerequisite
plus runtime detection — **never auto-installed**.

<!-- RECONCILE: Phase 3 owns the strategy seam, `select-caption.js`'s class consumption, and the
literal `<X-word-ms` inline-timing detection with the `--convert-subs srt` cleanup path. It also
gates the `asr` rung's default-on status on probe `[T5-ASR-TIMESTAMPS]`: if word-level timestamps
prove unusable for frame alignment, caption-absent falls to the degradation row above instead of
`asr`. Confirm the selection table and the named degradation field after Phase 3 lands. -->

## Failure patterns

| Pattern | Class |
| --- | --- |
| `No video could be found in this tweet` | fatal source |
| `No video formats found!` | fatal source |
| `Unsupported URL:` | fatal source |

The first two are post-content facts rather than transport failures; with the 0..N envelope they
usually resolve as a well-formed 0-result *before* reaching spawn-level classification, so seeing
them at all is the exception.

**Login-required is exactly three documented cases**, all raised the same way upstream:

1. NSFW / age-restricted media
2. A protected account — the cookie account must already follow the author
3. Any `not authorized` API message

Only these gate the cookie fallback. Nothing else on this page should trigger an auth retry.

## Rate-limit silent degradation

Under rate limiting X falls back to a syndication endpoint that returns a **partial result that
looks like a success**. Detection is compound — any of these signals, together, classify the
result as retryable with degradation metadata set, never as success:

- warning text `Rate-limit exceeded; falling back to syndication endpoint`
- missing `*_count` metadata fields
- a known multi-media post collapsing to a single entry

A legitimate single-video post must **not** flag: one entry with counts present and no warning is
an ordinary success.

## Link harvest and reply chains

Link harvest covers **post-text links only**.

**Reply-chain harvest is optional and agent-lane.** When the status is the head of a thread whose
replies carry material the digest needs, use `/x:read` to unroll the chain and fold the result in
as companion source material (`../../context/companion-primary-sources.md`). This is a judgment call per
watch, not a pipeline stage — the acquisition layer never walks replies.

## Auth and capabilities

| Capability | X |
| --- | --- |
| Extractor args | none |
| Comment harvest | not available |
| Browser-cookie-profile fallback | **not available** — a cookies file is the only auth route |

Because the browser-profile loop is unavailable, X must never iterate browser cookie profiles on
an auth failure. Supply `${user_config.yt_dlp_cookies_file}` (a Netscape `cookies.txt`, never
committed) or accept the login-required failure.

**Auth volatility.** X auth-fallback windows measure in **weeks to months**, not days: an
anonymous or cookie-based route that works today can stop working within that window, and the
recovery is a yt-dlp upgrade plus possibly a fresh cookies file. Treat a previously-working X
acquisition that starts failing as expected maintenance rather than a regression in this skill,
and check the yt-dlp version first.
