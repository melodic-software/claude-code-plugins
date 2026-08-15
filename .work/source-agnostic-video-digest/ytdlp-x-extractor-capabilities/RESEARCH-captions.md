---
section: captions
dispatch_ref: "lead-(b); original-dispatch-(a)"
question: "Caption availability, key shape, and how far back in time it actually holds."
verdict: best-effort-absent-more-often-than-present; no-date-cutoff-in-either-direction
confidence: high
evidence_tier: verified-firsthand + source
pre_2024_gap: RESOLVED (structurally, then confirmed by firsthand 2018 sample)
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# Captions / subtitles

## The extractor is a pure pass-through — DOCUMENTED, from source

- Sole source is `_extract_m3u8_formats_and_subtitles` inside `TwitterBaseIE._extract_variant_formats`
  (L47), reached **only when the variant URL contains `.m3u8`** (L46).
- The non-HLS branch returns `([f], {})` (L62) — a direct-`.mp4` variant **never** carries captions.
- There is **no twitter-specific caption code anywhere** in the file.

So X captions are exactly and only what X's HLS master playlist advertises as
`#EXT-X-MEDIA:TYPE=SUBTITLES`.

Enabled by commit `4bed43637` (PR #247, merged 2021-04-28), first release **2021.05.11**. That PR
was a repo-wide manifest-subtitle change, not twitter-specific. **There has never been a
twitter-specific caption regression, gate, or date check.**

## `automatic_captions` is never populated — DOCUMENTED

- Zero occurrences of `automatic_captions` in `twitter.py`.
- `_extract_m3u8_formats_and_subtitles` / `_parse_m3u8_formats_and_subtitles` return
  `(formats, subtitles)` only; neither can write `automatic_captions`.

**Consequence:** `--write-auto-subs` is a no-op for X. Use `--write-subs`. This holds even though
X itself marks the tracks `twitter.auto-generated` in the manifest.

## Language key derivation — DOCUMENTED, verbatim

`yt_dlp/extractor/common.py`, in `_parse_m3u8_formats_and_subtitles`:

```
2284  media_type, group_id, name = media.get('TYPE'), media.get('GROUP-ID'), media.get('NAME')
2285  if not (media_type and group_id and name):
2286      return
...
2307  lang = media.get('LANGUAGE') or 'und'
2308  subtitles.setdefault(lang, []).append(sub_info)
```

- **Key = the raw `LANGUAGE` attribute string.** No normalization, no BCP-47 validation.
- Fallback when `LANGUAGE` is absent is the literal `'und'`.
- `NAME` is a **presence gate only** (L2285) — a `TYPE=SUBTITLES` entry with no `NAME` is silently
  dropped entirely. `NAME` is never the key. `GROUP-ID` is never the key.

**VERIFIED FIRSTHAND — the key is NOT reliably `en`.** Observed across samples: `en`, `en-US`,
`en-GB`. Plus `und` is reachable by construction.

> **Contract obligation:** any consumer hardcoding `subtitles['en']` will silently miss most X
> captions. Match case-insensitively on an `en*` prefix, or take the first available key.

## The pre-2024 gap — RESOLVED

The dispatch flagged that a prior investigation confirmed `en` on three 2024–2026 samples but
sampled no pre-2024 post. Resolved structurally first, then confirmed firsthand.

**Structural answer:** caption presence is a property of **X's media pipeline, per video** — not of
the extractor. There is no date, duration, size, or version gate anywhere in the code path. An
extractor-side cutoff would be visible in source; none exists.

**Firsthand confirmation (I ran this myself, not a subagent):**

```
yt-dlp --list-subs https://twitter.com/LisPower1/status/1001551623938805763
  → [info] Available subtitles for 1001551417340022785:
    Language Formats
    en       vtt
```

That post is from **2018-05-29**. A 2018 post carries captions while several 2024–2026 posts I
probed carry none. **Any "captions only after date D" model is dead, in both directions.**

## Observed coverage — captions are SPARSE

Sampling across eras (mine plus a subagent's, all public posts):

| Upload | Post | Subtitles |
|---|---|---|
| 2018-05-29 | LisPower1/1001551623938805763 | **`en`** |
| 2022-09-29 | MesoMax919/1575560063510810624 | **`en-US`** |
| 2022-10-06 | oshtru/1577855540407197696 | none |
| 2022-12-06 | MunTheShinobi/1600009574919962625 | **`en-GB`** |
| 2023-11-15 | RobertKennedyJr/1724884212803834154 | **`en-US`** |
| 2024-05-15 | historyinmemes/1790637656616943991 | none |
| 2025-12-19 | TopHeroes_/2001950365332455490 | none |
| 2026-01-19 | boss_on_here/2013393873658118177 | none |

Four further posts I probed (2015, 2023×2, 2023) had **no subtitle track at all**. In my sampling
captions were **absent more often than present**, including on every 2024+ post sampled.

**Mechanism confirmed by manifest inspection.** Positive master playlist:

```
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="en-US (auto-generated)",DEFAULT=NO,FORCED=NO,
URI="/amplify_video/.../W-vd7ziyj4DA3AqL.m3u8",LANGUAGE="en-US",AUTOSELECT=YES,
CHARACTERISTICS="twitter.show-text-when-muted,twitter.auto-generated"
```

Negative master playlist: `EXT-X-MEDIA` lines exist for `TYPE=AUDIO` only — **no `TYPE=SUBTITLES`
line at all**. Nothing for yt-dlp to parse.

**NOT RESEARCHED / unresolved:** what predicts caption presence. The `ext_tw_video` vs
`amplify_video` hypothesis was tested and **fails** — both media paths contain positives and
negatives. No observable predictor was found. Stating this as an unresolved absence rather than
inferring one.

## Two extractor-side gaps (these ARE yt-dlp properties)

1. **Non-m3u8 variants** — the direct-`.mp4` branch never performs a subtitle lookup.
2. **Spaces and Broadcasts** — `TwitterSpacesIE` and `TwitterBroadcastIE` call the plain
   `_extract_m3u8_formats` wrapper, which at `common.py:2168-2172` **discards** any subtitles found
   and warns via `_report_ignoring_subs('HLS')`. **Structurally caption-free** regardless of what X
   serves. (Spaces captions are separately a known non-feature: #7902, open — X serves them as
   "chat history" in a custom JSON format requiring hundreds of requests per Space.)

## Cue-text contaminant

Positive tracks frequently inject a literal `(Captions are auto-generated)` **into the first cue
only** — verified firsthand in three separate downloaded VTT files. A consumer must strip it or it
lands at the head of the transcript.

## Contract implications

1. **A caption rung cannot assume coverage.** Captions are best-effort and, in my sampling, absent
   more often than present. An ASR fallback is required, not optional.
2. **No yt-dlp upgrade changes this.** Upgrading will never make captions appear on a post whose
   manifest lacks the tag. Do not treat missing captions as a version or breakage problem.
3. Accept `en`, `en-US`, `en-GB`, and `und` as caption keys.
4. Use `--write-subs`; `--write-auto-subs` is inert here.
5. Strip the leading `(Captions are auto-generated)` cue.
6. Spaces/Broadcast sources are structurally caption-free — route them straight to ASR.
