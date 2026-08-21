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

**The slice key is the status id from the URL — nothing else.** Same status → same slice, no
duplicates, whatever media the post resolves to. The metadata pair `(display_id, id)` rides
*alongside* the key rather than forming it: `source:displayId` is the status id, and each entry's
`id` is the media discriminator distinguishing entries within one post.

A quote tweet or retweet can surface the *quoted* post's media under the outer status. The
snowflake timestamp embedded in an id (`(id >> 22) + 1288834974657`, ms since epoch) is compared
between the URL's status id and the first media entry's id; a delta over **one hour** (media ids
are minted moments before their own post, so a small positive delta is ordinary composition lag)
flags probable aliasing under `source:snowflakeAliasing`, with the raw delta alongside so a
consumer can re-judge. Unflagged deltas are not recorded at all.

That flag lives on the acquisition envelope only — no slice artifact persists it today, so read it
from the acquisition result, not from disk.

## Result arity — 0..N videos per post

One status is **not** one video. Results are always a collection:

| Post shape | Result |
| --- | --- |
| Multi-video post | N entries |
| Single-video post | a one-entry collection — never a bare object |
| `/video/<n>` pinned | the honored index |
| No video, no outbound link | 0 entries; full post metadata (title, text, counts) |
| No video, outbound link present | 0 entries; **status id and the refused link only** |

A 0-entry result is **well-formed**, not an error and not null. It enqueues at preflight and
digests text-only end to end: `watching` and `vision` are marked skipped, so the digest rests on
text and research alone.

**The two 0-cases are not equally rich.** The no-link case comes from a real post info JSON, so
post text, title, and counts are all present. The link-post case does not: the extractor allow-list
refuses the delegated URL before any fetch, and yt-dlp writes **no info JSON** for an intermediate
url-result — so the post's own text and title are unrecoverable in that invocation, and provenance
is the URL's status id plus the refused outbound link (recorded under `source:blockedDelegations`
and appended to harvested links). Do not promise a link post's text to a downstream phase.

Envelope shape: 0..N `entries` plus one shared `metadata` object, whose namespace is open with
`source:`-prefixed keys reserved for source-specific fields. Transcripts travel as replayable
caption **file paths** (`captionPaths`, `caption`), never inline text.

## Provenance guard

X posts that link elsewhere would otherwise cause the downloader to chase the outbound target and
return someone else's media under this status's slice (yt-dlp upstream #9715). Two layers stop
that, and they resolve **differently**:

1. **Extractor allow-list (`--use-extractors twitter.*`)** — the primary guard, carried on every
   invocation (probe, media, queue preflight). yt-dlp refuses the delegated URL **without fetching
   it**, emitting `ERROR: No suitable extractor found for URL <url>`. This does *not* error the
   post: the status resolves as a well-formed 0-entry result with the blocked link recorded.
2. **Info-JSON extractor check** — defense in depth. A non-`twitter` info JSON on disk means layer
   1 failed, so the acquisition **hard-fails** with a provenance violation rather than digesting
   foreign media. This case is never a 0-result.

## Captions and transcript strategy

X captions are **platform ASR**, so the transcript ladder differs from YouTube's:

- `--write-subs` only. **Never** `--write-auto-subs` — X has no author-authored caption tier for
  it to reach, and requesting it produces misleading rung classification.
- Subtitle keys arrive as raw `LANGUAGE` values (`en`, `en-US`, `en-GB`, `und`). Never index
  `subtitles['en']` directly; match across the observed key set.
- An `.en.vtt` from X is **not** a manual-EN rung. The declared class drives the shared ladder,
  whose X rungs are `platform-asr-en` → `platform-asr-und` → STOP; every rung is auto-class, so
  nothing can misclassify as author-authored.
- The downloaded VTT carries X's inline word-timing tags (`<X-word-ms …>`) verbatim. Detecting
  that literal triggers a captions-only cleanup pass with `--convert-subs srt`, whose tag-free
  output is converted back into the VTT container the shared pipeline consumes. A failed cleanup
  fails the acquisition — captions are never silently lost.

Declared strategy default: `captions+repair`. Selection resolves per entry:

| Condition | Strategy |
| --- | --- |
| Captions present | `captions+repair` |
| Captions absent, ASR available **and** the media file on disk | `asr` |
| Captions absent, ASR or media missing | explicit degradation — digest without transcript, reason recorded in `transcriptDegradation`, never silent |

The media conjunct is load-bearing: the `transcript` action never downloads media, so the ASR rung
cannot run there at all — a caption-absent `transcript` run always degrades.

`captions+repair` runs proper-noun repair over the platform VTT, using the post text
(`description`) plus harvested links as the lexicon. The ASR rung is faster-whisper large-v3 at
`batch_size=8`, an optional closed-by-default capability delivered as a documented prerequisite
plus runtime detection — **never auto-installed**. The lexicon is repair-only: feeding it to ASR
as an `initial_prompt` was probed and yielded no net proper-noun gain while worsening a
hallucination, so the rung runs without one.

## Failure patterns

| Pattern | Class |
| --- | --- |
| `No video could be found in this tweet` | fatal source |
| `No video formats found` | fatal source |
| `Unsupported URL:` | fatal source |
| `Media #<n> is not a video` | fatal source |
| `Video #<n> is unavailable` | fatal source |

The first two are post-content facts rather than transport failures; with the 0..N envelope they
usually resolve as a well-formed 0-result *before* reaching spawn-level classification, so seeing
them at all is the exception. The last two are pinned-index selections of a photo or an
out-of-range slot — deterministic post facts, permanent, never transient.

**Login-required is exactly three documented cases**, all raised the same way upstream:

1. NSFW / age-restricted media
2. A protected account — the cookie account must already follow the author
3. Any `not authorized` API message

Only these gate the cookie fallback. Each pattern is anchored to a `[twitter]`-tagged `ERROR:`
line, so attacker-influenced text elsewhere on stderr — a hostile URL echoed back in a refusal
line, say — can never classify as login-required and provoke a cookie-bearing retry.

## Rate-limit silent degradation

Under rate limiting X falls back to a syndication endpoint that returns a **partial result that
looks like a success**. **Either** signal alone classifies the result as retryable with
degradation metadata set, never as success:

- the warning text `Rate-limit exceeded; falling back to syndication endpoint` on stderr
- a post payload missing **both** the repost and comment counts — judged only when the payload is
  genuinely post-level (a playlist or metadata-only info), never when a media-entry dict is
  standing in for the post, and never on a blocked delegation, which has no payload at all

Multi-media collapse is an **output** of that judgment, not a third input: once a result is
degraded, a single entry marks it as a possible collapse. So a legitimate single-video post does
not flag — one entry with counts present and no warning is an ordinary success.

## Link harvest and reply chains

Link harvest covers **post-text links only**.

**Reply-chain harvest is optional and agent-lane.** When the status is the head of a thread whose
replies carry material the digest needs, invoke `/x:read` via the Skill tool to unroll the chain
and fold the result in
as companion source material (`../../context/companion-primary-sources.md`). This is a judgment call per
watch, not a pipeline stage — the acquisition layer never walks replies.

## Auth and capabilities

| Capability | X |
| --- | --- |
| Extractor args | none |
| Extractor allow-list | `twitter.*` — declared, and carried on every invocation |
| Comment harvest | not available |
| Browser-cookie-profile fallback | **not available** — a cookies file is the only auth route |
| Media-optional (0-media is well-formed) | **available** — every yt-dlp call passes `--ignore-no-formats-error` |

Because the browser-profile loop is unavailable, X must never iterate browser cookie profiles on
an auth failure. Supply `${user_config.yt_dlp_cookies_file}` (a Netscape `cookies.txt`, never
committed) or accept the login-required failure.

**Auth is not a precondition.** A public status acquires media, captions, and metadata
**anonymously** — no cookies, no account, no extractor args (verified 2026-08-15 against yt-dlp
2026.07.04). Cookies buy exactly the three login-required cases above and nothing else, so do not
demand them up front.

**Auth volatility.** X auth-fallback windows measure in **weeks to months**, not days: an
anonymous or cookie-based route that works today can stop working within that window, and the
recovery is a yt-dlp upgrade plus possibly a fresh cookies file. Treat a previously-working X
acquisition that starts failing as expected maintenance rather than a regression in this skill,
and check the yt-dlp version first.
