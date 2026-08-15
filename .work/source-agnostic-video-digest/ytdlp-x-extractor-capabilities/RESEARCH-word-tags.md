---
section: word-tags
dispatch_ref: "original-dispatch-(b); no lead-letter (folded under captions in the re-lettered list)"
question: "The nonstandard per-word VTT cue tags X emits: documented? stable? do generic WebVTT parsers handle them?"
verdict: undocumented-but-real-and-stable-shape; conformant-parsers-drop-them-silently; yt-dlp-itself-does-NOT-strip
confidence: high (semantics + parser behavior verified firsthand); low (presence predictor unresolved)
evidence_tier: verified-firsthand + spec-text + vendor-source
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# `<X-word-ms>` per-word cue tags

## Shape — CORRECTED against the dispatch

The dispatch reported `<X-word-ms ms=120,180 index=1 character_ranges=0-5>`. That sample is
**not consistent with any real X output I captured**: it has 2 `ms` values against 1 character
range, an arity mismatch that never occurs in real data. It also omits the closing tag.

**Real captured shape** (from `LisPower1/1001551623938805763`, 48 tags in one file):

```
<X-word-ms ms=380,319,260,280,199,500,200,139,320,540 index=1
 character_ranges=0-8,9-14,15-23,24-27,28-35,36-43,44-47,48-51,52-56,57-59>President Trump accusing the special counsel and his team of</X-word-ms>
```

**The tag WRAPS the cue text and has a matching closing tag.**

## Semantics — RESOLVED FIRSTHAND (prior research could not pin these)

Verified programmatically across all 48 tags in the captured file:

| Attribute | Meaning | Verification |
|---|---|---|
| `ms` | **per-word DURATIONS in milliseconds** — not timestamps, not offsets | `sum(ms) ≈ cue duration` in **40/48** cues (example: sum 3137 ms vs cue 3140 ms) |
| `character_ranges` | **inclusive `start-end` offsets into the wrapped text**, one per word | slicing reproduces the words; `0-8` = "President" (9 chars) |
| arity | `len(ms) == len(character_ranges)` — one entry per word | **48/48** |
| `index` | **the CUE index**, 1-based — NOT a word index | observed values 1,2,3…8 across the file's cues |

Ranges may include the leading space of a word (`9-14` → `" Trump"`).

## Documentation status: UNDOCUMENTED by X

No vendor documentation found anywhere (developer.x.com returned HTTP 402 to the probing agent — a
blocked probe, not a null result; X engineering blog and help center surfaced nothing).

**But it is real and internally depended upon.** X's own open-sourced recommendation repo hardcodes
it — `xai-org/x-algorithm`, `grox/libs/video_tools/subtitles.py`:

```python
X_WORD_MS_PATTERN = (
    r"<X-word-ms ms=([^>]+) index=\d+ character_ranges=([^>]+)>([^<]+)</X-word-ms>"
)
```

This is X **consuming** the format, not specifying it — strong evidence the construct is stable
enough to hard-code, but **not documentation**. Note their regex discards `index` and matches the
closing tag, independently corroborating the corrected shape above.

GitHub code search for the literal string returns **14 results**, all consumer/stripping code
(`CheshireMew/MediaFlow`, `samuxbuilds/capsummarize`, `aitkn/xtil`, `HRussellZFAC023/yomu-reader`,
`erikschlegel/jarvis-vault`, `luisitoys12/DowP_Downloader`, `Leosce/HearMeOut`,
`choisungwook/akbun-aitools`).

## Stability and presence — PARTIALLY UNRESOLVED

**Shape stability: no evidence of any change.** All independent observations agree on
`ms=` / `index=` / `character_ranges=` with a closing tag.

**Presence is per-track and I could NOT establish the predictor.** Two hypotheses tested and
**both falsified firsthand**:

| Hypothesis | Status |
|---|---|
| "appears only on auto-generated tracks" | **FALSIFIED** — the 2023 RFK track is explicitly auto-generated (`CHARACTERISTICS=...twitter.auto-generated`, and its first cue literally reads `(Captions are auto-generated)`) yet contains **zero** `X-word-ms` |
| "recent — first seen July 2026, so newer tracks have it" | **FALSIFIED** — the **2018** post's track has **48** tags; 2022 and 2023 tracks have none |

My firsthand sample (n=4):

| Post | Lang key | `X-word-ms` | `(Captions are auto-generated)` marker |
|---|---|---|---|
| 2018 LisPower1 | `en` | **48** | **no** |
| 2022 MesoMax919 | `en-US` | 0 | yes |
| 2022 MunTheShinobi | `en-GB` | 0 | yes |
| 2023 RobertKennedyJr | `en-US` | 0 | yes |

**Observed correlation (n=4, NOT established):** a bare `en` key with no auto-generated marker
correlates with tag presence; regional `en-XX` keys with the marker correlate with absence. One
third-party report (`aitkn/xtil`, 2026-07-09) claims an `en-gb` track **with** tags, which
contradicts it. Treat as a hypothesis; the cheap runtime test is "does the payload contain
`<X-word-ms`", not any inference from the language key.

**NOT RESEARCHED:** whether creator-uploaded (non-ASR) caption tracks ever carry the tag.

## Parser behavior

### W3C spec: a conformant parser DROPS the whole tag — VERIFIED against spec text

Traced through the WebVTT cue text tokenizer (Candidate Recommendation Draft, 2026-05-20):

- *WebVTT tag state* → *start tag state* accumulates the name with **no character restriction**, so
  `X-word-ms` (hyphens, uppercase) tokenizes cleanly.
- *start tag annotation state* — "Anything else: Append c to buffer" — **swallows
  `ms=380,... index=1 character_ranges=0-8,...` wholesale.** No quoting is required.
- Cue text parsing rules then match the tag name against `c`, `i`, `b`, `u`, `ruby`, `rt`, `v`,
  `lang`, and otherwise: **"Ignore the token."** Nothing is appended to the node tree.

So: **clean text out — no stray angle brackets, no garbage, no parse failure.** (The file is
non-conformant *as authored* — an undefined span carrying an annotation it isn't entitled to — but
parsers are deliberately error-tolerant here, which is why the construct is viable.)

### Real parsers

| Parser | Behavior | Evidence |
|---|---|---|
| **ffmpeg** | Skips any unrecognized `<…>` whole | source `libavcodec/webvttdec.c` + **verified by execution** |
| **Chromium** | `TokenToNodeType()` → `kNone` → token discarded | source `vtt_parser.cc` |
| **Mozilla vtt.js** (also video.js) | `TAG_NAME[type]` undefined → `return null` → skipped | source `lib/vtt.js` |
| **webvtt-py** | `.text` strips via `re.sub('<.*?>', '', raw_text)`; **`.raw_text` preserves** | source `webvtt/models.py:102,196` |

### yt-dlp itself does NOT strip cue tags — the actionable conditional

`yt_dlp/webvtt.py` `CueBlock` docstring is explicit: **"A cue block. The payload is not
interpreted."** There is no `re.sub(r'<[^>]+>', ...)` applied to subtitles anywhere. (`clean_html`
exists but is for descriptions, not subtitle files.)

- **`--write-subs` with no conversion → the tags land on disk verbatim.**
  **VERIFIED FIRSTHAND**: `dl_test.en.vtt` (8,385 bytes) written by yt-dlp 2026.07.04 contains all
  48 raw tags.
- **`--convert-subs srt` → clean text**, because `FFmpegSubtitlesConvertorPP` shells out to ffmpeg,
  which does the stripping (verified by execution).

### Two ffmpeg hazards (verified by execution, worth knowing)

1. **A dangling `<` truncates the rest of the cue.** `if (!tag_end) break;` discards everything
   after an unclosed `<`. Relevant because X captions arrive as HLS VTT segments — if a tag were
   ever split across a fragment boundary, that cue silently loses its tail. No evidence this
   happens today (observed: one segment covering the whole video).
2. **Tag matching is a `strncmp` PREFIX match**, so any unknown tag whose name merely *starts with*
   `i`, `b`, or `u` gets spurious formatting injected. `X-word-ms` is safe only because it starts
   with `X` — a future rename could silently corrupt every caption.

## Contract implications

1. **Do not hand raw X VTT to a naive consumer** — yt-dlp will not have stripped it.
2. **Two clean options**, pick deliberately:
   - `--convert-subs srt` → clean text, **per-word timings discarded** (the tag's entire purpose).
   - Parse deliberately with the xai-org regex → keep word-level timings (group 1 `ms`, group 2
     `character_ranges`, group 3 text).
3. **Detect, don't assume**: test for the literal `<X-word-ms` in the payload. Presence is per-track
   and no reliable predictor exists.
4. Independently of these tags, strip the `(Captions are auto-generated)` first-cue marker.
