---
section: id-semantics
dispatch_ref: "lead-(d); original-dispatch-(d)"
question: "URL status id vs reported id; quote-tweet and retweet behavior; which id is stable and joinable back to the post?"
verdict: display_id-is-the-stable-join-key; id-is-usually-the-MEDIA-id; both-alias-under-retweets-and-quotes
confidence: high
evidence_tier: verified-firsthand + ytdlp-own-tests + source
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# ID semantics — the durable slice key

**The id in the URL is NOT the id the extractor reports as `id`.** This is the single most
consequential finding for slice-key design.

## The mapping — DOCUMENTED, from source + verified firsthand

| Field | Value | Origin |
|---|---|---|
| `display_id` | **always the URL's status id (`twid`)** | explicitly set at L1371 and L1373 |
| `id` — entry from `extended_entities` / `unified_card` | **the MEDIA id** | `extract_from_video_info` returns `'id': media_id` (L1265); `{**info, **data}` lets `data` overwrite `info['id']` |
| `id` — entry from a card / vmap | **the STATUS id** | that branch (L1340) yields **no** `id` key, so `info['id'] = twid` (L1223) survives |
| `id` — playlist container | **the STATUS id** | `playlist_result(entries, **info)` (L1390); `info['id']` is `twid` |
| `display_id` — playlist container | **absent (`None`)** | `info` carries no `display_id` |

Also: `_old_archive_ids = [make_archive_id(self, twid)]` is set on the **first entry only** (L1382),
preserving the pre-multi-video behavior where `id` was the status id.

### Evidence

**1. yt-dlp's own first test asserts the split** (`twitter.py` `_TESTS[0]`):

```
'url': 'https://twitter.com/freethenipple/status/643211948184596480',
'info_dict': { 'id': '643211870443208704',
               'display_id': '643211948184596480', ... }
```

**2. VERIFIED FIRSTHAND — 2-video post** (`primevideouk/1578401165338976258`):

```
container:  _type=playlist  id=1578401165338976258  display_id=None
entry 1:    id=1578400766095654915  display_id=1578401165338976258
entry 2:    id=1578391494028890119  display_id=1578401165338976258
```

**3. VERIFIED FIRSTHAND — card-derived post** (`CAF_Online/1349365911120195585`, poll2choice_video):

```
id=1349365911120195585   display_id=1349365911120195585
```

Identical, and both equal the status id — while the actual media lives under
`amplify_video/1349360978069245954`. This confirms the card branch does **not** report a media id.

**4. VERIFIED FIRSTHAND — 2018 post**: `--list-subs` reported
`Available subtitles for 1001551417340022785` for URL status `1001551623938805763` — the media id
again differing from the status id.

## Two aliasing hazards

### 1. Retweets — the whole status is REPLACED (INFERRED-FROM-SOURCE)

`_extract_status` ends at L1206:

```python
return traverse_obj(status, 'retweeted_status', None, expected_type=dict) or {}
```

`traverse_obj` with multiple paths returns the **first** match, so when `retweeted_status` exists
the **entire status object becomes the retweeted original**. Consequences:

- `twid` / `display_id` remain the **retweet's** status id (they come from the URL, L1209).
- `uploader`, `uploader_id`, `channel_id`, `timestamp`, `title`, `description`, all counts, and all
  media belong to the **original** post.

So for a retweet, `display_id` identifies a post whose author and text are **not** the ones
reported. `display_id` is a join key to the *URL*, never a content-identity key.

> Labeled **INFERRED-FROM-SOURCE**: my reading of L1206 is direct and unambiguous, but I did not
> probe a live retweet URL to confirm end-to-end.

### 2. Quote-tweets — media is drawn from the QUOTED post (VERIFIED)

```
1348  videos = traverse_obj(status, (
1349      (None, 'quoted_status'), 'extended_entities', 'media', lambda _, m: m['type'] != 'photo', {dict}))
```

The `(None, 'quoted_status')` branch traverses **both** the status itself and its `quoted_status`,
**concatenating** the media of both. A quote-tweet whose own post has no media but whose quoted post
has video yields the **quoted post's** media under the quoting post's `display_id`.

This is exactly the dispatch's observation that "a quote-tweet URL resolved to a DIFFERENT status's
media."

- **DOCUMENTED corroboration:** issue **#14664** (2025-10-19, **still open**) — "Twitter downloads
  quoted tweet despite `--no-playlist`".
- **VERIFIED FIRSTHAND:** `boss_on_here/2013393873658118177` (status dated 2026-01-19) reported
  media id `2012261390430408706`, which snowflake-decodes **earlier** than the status id —
  i.e. the media belongs to an earlier, different post.

## Snowflake note (useful, verified)

X status ids are snowflake-encoded: `timestamp_ms = (id >> 22) + 1288834974657`. I used this to date
every sample in this research. It means **a post's creation date is derivable from the id alone**,
with no API call — useful for a digest pipeline and for detecting the quote/retweet aliasing above
(media id materially older than status id is a strong signal).

## Contract implications — recommended slice key

1. **`display_id` is the only field stably equal to the URL's status id**, so it is the correct
   **join key back to the post**. It is present on every entry and on the single-video result.
2. **`display_id` is absent on the playlist container** — read it from entries, not the container,
   or fall back to the container's `id`.
3. **`display_id` is NOT a content-identity key.** Retweets and quote-tweets alias: the same
   `display_id` can front content authored in a different status.
4. **`id` is not uniform** — media id for `extended_entities`/`unified_card` videos, status id for
   card/vmap videos. It is therefore not safe as a sole key either.
5. **Recommendation: key the slice on the tuple `(display_id, id)`.** That is unique per media
   within a post, stable across runs, and joinable back to the source URL. If the pipeline must
   also assert that content belongs to the post it is attributed to, compare the snowflake dates of
   `display_id` and `id` and flag the mismatch as a quote/retweet.
