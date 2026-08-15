---
section: playlist-shape
dispatch_ref: "lead-(c); original-dispatch-(c)"
question: "When does the extractor return _type: playlist, what do entries contain, and what produces a zero-entry playlist?"
verdict: playlist-iff-2-or-more-entries; zero-entry-playlist-is-a-DOWNSTREAM-artifact-not-an-extractor-state
confidence: high
evidence_tier: verified-firsthand + source
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# Playlist / multi-media post shape

All line refs are `_real_extract`, `yt_dlp/extractor/twitter.py` L1208-1390.

## When the playlist branch is entered — DOCUMENTED, from source

`_yes_playlist(twid, selected_index, video_label='URL-specified video number')` at L1351.

`_yes_playlist` (`common.py:4036`) begins `if not playlist_id or not video_id: return not video_id`.
`playlist_id` is `twid` (always truthy); `video_id` is `selected_index`, which is the `/video/N`
capture group from `_VALID_URL`:

```
_VALID_URL = _BASE_REGEX + r'(?:(?:i/web|[^/]+)/status|statuses)/(?P<id>\d+)(?:/(?:video|photo)/(?P<index>\d+))?'
```

- **No `/video/N` in the URL** → `selected_index is None` → returns `True` → playlist branch.
  This is the case for every ordinary X post URL.
- **`/video/N` present** → falls through to the `--no-playlist` check; with the default
  (`noplaylist` false) it *still* returns `True`. Honouring the index requires an explicit
  `--no-playlist`. (Corroborating tracker item: #15402, "Single video link is treated as playlist,
  `--no-playlist` is ignored", fixed 2025-12-29 by `ce9a3591f`.)

## `_type: playlist` is returned IFF `len(entries) >= 2` — DOCUMENTED

```
1373  entries = [{**info, **data, 'display_id': twid} for data in selected_entries]
1374  if not entries:            # → see "zero extractor entries" below
1382  entries[0]['_old_archive_ids'] = [make_archive_id(self, twid)]
1384  if len(entries) == 1:
1385      return entries[0]      # plain video dict, NOT a playlist
1387  for index, entry in enumerate(entries, 1):
1388      entry['title'] += f' #{index}'
1390  return self.playlist_result(entries, **info)
```

- 1 entry → a plain video dict. A single-video post is **never** a playlist.
- ≥2 entries → `playlist_result`, and **every** entry title gets `' #N'` appended (1-based).

## What `entries` contain — DOCUMENTED

Each entry is `{**info, **data, 'display_id': twid}` — the full post-level metadata dict merged
with the per-media dict, so every entry carries the post's title, description, uploader, timestamp,
counts, tags.

`selected_entries` (L1352) is the concatenation of two generators:

```
1348  videos = traverse_obj(status, (
1349      (None, 'quoted_status'), 'extended_entities', 'media', lambda _, m: m['type'] != 'photo', {dict}))
1352  selected_entries = (*map(extract_from_video_info, videos), *extract_from_card_info(status.get('card')))
```

1. **`extended_entities.media`**, non-photo, traversed over **both the status AND `quoted_status`**
   — see the id-semantics section; this is a correctness hazard, not just a shape note.
2. **Card-derived entries** from `extract_from_card_info`, which may yield `{'_type': 'url', ...}`
   redirect entries for `player`, `periscope_broadcast`, `broadcast`, `audiospace`, and `summary`
   cards, or a formats dict for `unified_card` / amplify / vmap cards.

**VERIFIED FIRSTHAND** on a 2-video post (`primevideouk/1578401165338976258`):

```
_type: playlist   id: 1578401165338976258   display_id: None   n_entries: 2
  entry id=1578400766095654915  display_id=1578401165338976258  nfmt=5
  entry id=1578391494028890119  display_id=1578401165338976258  nfmt=5
```

## Zero entries FROM THE EXTRACTOR — the branch that is NOT a playlist

```
1374  if not entries:
1375      expanded_url = traverse_obj(status, ('entities', 'urls', 0, 'expanded_url'), expected_type=url_or_none)
1376      if not expanded_url or expanded_url == url:
1377          self.raise_no_formats('No video could be found in this tweet', expected=True)
1378          return info
1380      return self.url_result(expanded_url, display_id=twid, **info)
```

Zero extractor entries produces **either** an error/`info` dict **or** a `_type: url` redirect —
**never** a playlist. See the failure-taxonomy section; L1380 is the dangerous off-platform chase.

## A zero-entry playlist is a DOWNSTREAM artifact — VERIFIED FIRSTHAND

`playlist_result` is structurally unreachable with an empty list, so `entries: []` **cannot**
originate in the extractor. It is produced by YoutubeDL-side item handling.

**Reproduced** — `-I 5` (playlist-items filter selecting nothing) against the 2-entry post above:

```
_type: playlist   id: 1578401165338976258   n_entries: 0   playlist_count: 2
```

> **`playlist_count` is the discriminator.** `entries == [] and playlist_count > 0` means "the
> extractor found N media and this run filtered or failed them all" — it does **not** mean "this
> post has no video". Failing closed on `entries == []` alone would misclassify the post.

Any downstream filter has this effect: `--playlist-items`/`-I`, `--match-filter`, `--dateafter`,
`--break-on-*`.

**NOT RESEARCHED:** whether an all-entries-*failed* playlist (as opposed to filtered) also yields
`entries: []`. I tested `--ignore-errors` against a *healthy* playlist and both entries survived
intact; I did not construct a playlist whose entries all fail (which would require a post with ≥2
card entries resolving to unsupported external URLs). The `playlist_count` discriminator holds
regardless of which mechanism empties the list.

## Contract implications

1. **Fail-closed-vs-sub-slices:** the extractor gives sub-slices only at `len(entries) >= 2`. A
   single-video post arrives as a plain video dict, so the adapter must handle both shapes — the
   presence of `_type` is the branch, not the media count.
2. **Do not fail closed on `entries == []`.** Read `playlist_count` first.
3. Entry titles are mutated with `' #N'` in the multi-entry case — do not treat entry title as
   equal to post title.
4. Card entries may be `_type: url` pointing off-platform; a playlist is not guaranteed to be
   homogeneous X media.
