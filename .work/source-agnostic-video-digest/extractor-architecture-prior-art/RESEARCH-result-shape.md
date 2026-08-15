---
topic: extractor-architecture-prior-art
section: result-shape
abstract: yt-dlp's TwitterIE solves the 0/1/N-videos-per-post problem for our exact second source in five branches; take all five cases but reject its arity collapse, and give the four error states distinct types from day one.
claims:
  - claim: "yt-dlp's info dict requires only id, title, and one of formats/url; every other field is optional and None means absence. The _type values are video (default), playlist, multi_video, url, url_transparent, each specified only in prose."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/extractor/common.py:120-128 (required fields), :495-529 (_type paragraphs)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "TwitterIE._real_extract handles a post with 0, 1, or many videos in five distinct branches, including delegating to another extractor when the post has no video but an outbound link, and returning a metadata-only result when it has neither."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/extractor/twitter.py:1348-1390 (local checkout @ 5d6b8c8)"
        tier: 0
        pool: "yt-dlp source"
      - url: "yt_dlp/extractor/common.py:4036-4051 (_yes_playlist), :1265-1273 (raise_no_formats)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "Streamlink expresses four distinct adapter states with four distinct types, and NoPluginError deliberately does not inherit from PluginError."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "src/streamlink/exceptions.py; src/streamlink/plugin/plugin.py:439-442; streamlink_cli/main.py:519-541"
        tier: 0
        pool: "streamlink source"
      - url: "https://github.com/streamlink/streamlink/pull/5088"
        tier: 1
        pool: "streamlink maintainers"
  - claim: "Streamlink's maintainers record in-tree that conflating transport failure with schema-validation failure under PluginError was a mistake."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "src/streamlink/exceptions.py:7 — '# TODO: don't use PluginError for failed HTTP requests or validation schema failures'"
        tier: 0
        pool: "streamlink source"
      - url: "https://github.com/streamlink/streamlink/issues/5047"
        tier: 1
        pool: "streamlink maintainers"
  - claim: "Only yt-dlp — the one system dispatching purely on URL — returns a whole result object; gallery-dl, Pygments, and Tika all stream and all keep a separate metadata channel."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/message.py + job.py:222 (3-tuple message stream)"
        tier: 0
        pool: "gallery-dl source"
      - url: "Tika parser.html design criteria; org.apache.tika.parser.Parser SAX ContentHandler signature (3.3.2)"
        tier: 1
        pool: "Apache Tika"
produced_by: phase-2-targeted-and-falsification
---

# The result shape, arity, and error classification

## The info dict — documented, Tier 0

`common.py:121-128`, the entire required set:

> For a video, the dictionaries must include the following fields:
> `id` — Video identifier.
> `title` — Video title, unescaped. Set to an empty string if video has no title as opposed to "None"
> which signifies that the extractor failed to obtain a title
> Additionally, it must contain either a `formats` entry or a `url` one

And the hedge that defines the rest (`common.py:490-492`):

> Unless mentioned otherwise, the fields should be Unicode strings.
> Unless mentioned otherwise, None is equivalent to absence of information.

Note the `title` subtlety: `""` and `None` mean **different** things — no title versus extraction
failed. That distinction is carried in prose only, and nothing enforces it.

## `_type` semantics — prose-only, five values

| `_type` | Meaning (`common.py:495-529`) |
|---|---|
| *(absent)* / `video` | a single video — the default |
| `playlist` | multiple videos. Requires `entries`: a list, an iterable, **or a `PagedList`**. Optional `playlist_count` — *"If not given, YoutubeDL tries to calculate it from entries"* |
| `multi_video` | multiple videos forming one show (opera acts, TV episode parts). Has `entries` **and** all the keys required of a video, simultaneously |
| `url` | *"the video must be extracted from another location, possibly by a different extractor."* Only required key is `url`; optional `ie_key` names the target class |
| `url_transparent` | same as `url`, but *"the given additional information is more precise than the one associated with the resolved URL"* — for a site embedding a video service that lacks useful titles |

Constructed via two helpers (`common.py:1275-1311`) — `url_result(url, ie=None, …, url_transparent=False)`
and `playlist_result(entries, …, multi_video=False)`. **`playlist` accepts a lazy iterable**, which is
how yt-dlp gets streaming behaviour out of a whole-object contract.

## Arity — the crown jewel, and a deliberate departure from it

`yt_dlp/extractor/twitter.py:1348-1390` solves *exactly* the 0/1/N problem for *exactly* our second
source. Five branches, read directly:

| Case | Return | Line |
|---|---|---|
| N videos, all wanted | `self.playlist_result(entries, **info)` → `_type: 'playlist'`, titles suffixed `#1`, `#2`… | 1387-1390 |
| exactly 1 | **the bare video dict** — arity collapsed | 1384-1385 |
| user pinned an index (`/status/…/video/2`) | that single video; index validated, `ExtractorError('Media #N is not a video', expected=True)` otherwise | 1353-1371 |
| 0 videos, tweet has an outbound link | `self.url_result(expanded_url, display_id=twid, **info)` → **delegate to another adapter** | 1374-1380 |
| 0 videos, no link | `self.raise_no_formats('No video could be found in this tweet', expected=True)` then `return info` — **metadata-only result** | 1377-1378 |

Two supporting mechanisms:

- **`TwitterIE._VALID_URL` carries `(?P<index>\d+)`** (`twitter.py:271`) — the URL shape itself encodes
  *which item in this post*, so one-URL→N-items disambiguation is baked into the claim.
- **`_yes_playlist()` (`common.py:4036-4051)`** is the adapter *asking the pipeline's policy* rather
  than deciding unilaterally: it reads `--no-playlist`, honours a smuggled `force_noplaylist`, and emits
  the user-facing *"add --no-playlist to download just the video"* hint. The adapter shapes the result;
  the **pipeline owns the policy**.

### Take the five cases; reject the collapse

**Recommendation: always return a uniform 0..N collection with a DECLARED arity; never collapse 1 to a
bare object.** Reasoning, from evidence already in this corpus:

- The collapse is exactly why every yt-dlp consumer must branch on `_type` before it can read anything.
- It is why `_RETURN_TYPE` had to be **reverse-engineered from test fixtures**
  (`common.py:3822-3832` — see `RESEARCH-required-vs-provided.md`), and why `is_single_video()` returns
  `None` for "unknown".
- A convenience accessor can collapse at the call site. The contract must not.

## Envelope shape — streaming vs whole object

**Only yt-dlp returns a whole object, and it is the only system dispatching purely on URL.** The three
content-driven systems all stream:

| System | Result | Streaming? | Metadata channel |
|---|---|---|---|
| yt-dlp | `info_dict` — one object | no (lazy `entries` aside) | fields in the same dict |
| gallery-dl | generator of uniform 3-tuples `(msg_id, str, dict)` | yes, with bounded-queue backpressure | the dict, with reserved `_`-keys |
| Pygments | `(index, tokentype, value)` generator | yes | none |
| Tika | XHTML SAX events into a caller-supplied `ContentHandler` | yes (push) | `Metadata` in/out param |

For a digest pipeline the acquisition unit (a post) is small but the **transcript is large**, which
argues for: a fixed required core + an **open metadata namespace**, items as a 0..N collection, and the
transcript as a **replayable file path**, not an in-memory string.

Supporting rules from the contrast set:

- **Standardize the shape, keep the vocabulary open, with parent-fallback.** Pygments' `Token.Foo.Bar`
  synthesizes new token subtypes via `__getattr__`; formatters walk up to a known parent, so a new
  adapter can emit a type no consumer has seen and every consumer still renders it sanely. Tika: fixed
  XHTML skeleton, arbitrary `Metadata` keys.
- **Extend through reserved payload keys, not new result types.** gallery-dl's message enum has **3
  live constants**; `Message.Metadata` was added for one site (patreon) and removed 14 months later
  (`311005c3`, 3 files, 25 lines). All real per-site extensibility lives in underscore-prefixed keys in
  the ordinary metadata dict — `_http_headers`, `_http_method`, `_http_expected_status`, `_fallback`,
  `_extractor`, `_ytdl_info_dict`, `_ugoira_frame_data`. Retired message numbers stay commented out and
  are **never reused**.
- **Multi-attempt dispatch requires a replayable input.** Tika's `ParserUtils.ensureStreamReReadable`
  buffers to disk *"to permit Parsers 2+ to be able to read the same data"*; Tika 4 hard-codes
  `TikaInputStream` into the interface signature rather than documenting the requirement in prose.
  **Download once to a local file; hand adapters a replayable path.**
- **Provenance is written by the dispatcher, not the adapter.** Tika `TIKA_PARSED_BY`,
  `EMBEDDED_EXCEPTION`, `WRITE_LIMIT_REACHED`; FFmpeg `AVFormatContext->probe_score`. Record which
  adapter was chosen, why, and any truncation, on every digest.
- ⚠️ **gallery-dl sharp edge worth not copying:** the metadata dict is **mutated and re-yielded**, not
  copied (`status["num"] = …; yield`). Consumers must not retain references across yields, and that is
  an *unwritten* part of the contract.

## Metadata split from results — and declare the fetch seam

Streamlink splits four metadata properties (`id`/`author`/`category`/`title`, `plugin.py:297-304`) from
the returned stream map, read through normalizing getters (`.strip()`, added by #4117 because
whitespace corrupts `--output '{title}'`). **That split is what lets `Plugin.streams()` sort, dedupe,
alias, and inject `best`/`worst` without knowing anything about the source** (`plugin.py:392-529`).

**But the base declares only *where* metadata lands, not *how or when* it is fetched** — so
`plugins/twitch.py:873-886` monkeypatches its own instance's method table in a `setattr` loop to make
metadata lazy:

```python
for metadata in "id", "author", "category", "title":
    setattr(self, f"get_{metadata}", method_factory(getattr(parent, f"get_{metadata}")))
```

**If you split metadata from results, declare the fetch seam too** — an optional `fetch_metadata()` the
pipeline calls, or lazy properties — so no adapter has to rewrite its own method table.

## Error classification — the strongest convergence, with a maintainer admission

**Four states, four distinct types, from day one.** Streamlink's taxonomy, read from source:

| State | Expression | Handled where |
|---|---|---|
| **not mine** | *no exception* — no matcher matched, adapter never constructed; router raises `NoPluginError` | `session/session.py:125` |
| **mine, nothing here** | return `None`/empty, or `raise NoStreamsError` | `plugin.py:439-440` → `{}` |
| **mine, source broke** | `PluginError` — raised directly, or auto-derived from any `OSError`/`ValueError` (including every schema `ValidationError`) | `plugin.py:441-442`; CLI logs and **retries** |
| **mine, unrecoverable — stop** | `FatalPluginError(PluginError)` | `main.py:519-541` re-raises **past** the retry loop |
| *(post-selection)* | `StreamError` — raised by `Stream.open()` | separate CLI handlers |

`NoPluginError` **does not** inherit from `PluginError` — changed in #5088 (5.2.0) because *"it
shouldn't inherit from `PluginError`, because it's something entirely different."* Both are siblings
under `StreamlinkError`.

`FatalPluginError` is honored, not decorative (`streamlink_cli/main.py:519-541`):

```python
try:
    streams = fetch_streams(plugin)
except FatalPluginError:
    raise
except PluginError as err:
    log.error(err); streams = None
```

With `--retry-streams`, an ordinary `PluginError` is logged and retried on an interval; a
`FatalPluginError` breaks out immediately. `Plugin.input_ask` raises it when user input is required but
unavailable — exactly the case retrying can never help.

### The recorded regret — verbatim, in the tree today

`src/streamlink/exceptions.py:7`:

```python
# TODO: don't use PluginError for failed HTTP requests or validation schema failures
```

Tracked as issue #5047. The maintainers consider it wrong that "the network failed", "the response
shape changed", and "the source's logic said no" all arrive as one class. **Take the lesson, not the
implementation: give schema failure and transport failure distinct types from day one.**

Streamlink's own wart to avoid: `resolve_url` (`session/session.py:111-125`) swallows transport failures
with `except PluginError: pass` and falls through to `raise NoPluginError`, so a network outage during
routing is reported to the user as *"No plugin can handle URL: …"*.

### yt-dlp does the same job worse — a flag where a taxonomy belongs

`common.py:1246-1273` — `raise_login_required`, `raise_geo_restricted`, `raise_no_formats` all funnel
into `ExtractorError(msg, expected=True)`. `expected` is a **boolean on one exception type** carrying
the entire "this is a normal condition, not a bug" signal. The taxonomy that does exist
(`utils/_utils.py`) is `ExtractorError` → `UnsupportedError`, `RegexNotFoundError`, `GeoRestrictedError`,
`UserNotLive` — organized by *cause*, not by *what the caller should do*.

Note also the `metadata_available` parameter on `raise_login_required` / `raise_geo_restricted`: when
the caller passed `--ignore-no-formats-error`, these downgrade to a warning and return, so the adapter
still yields a metadata-only result. **That is the same 0-items-but-valid-result case TwitterIE hits**,
reached by a different route — evidence the case is common enough to deserve first-class expression.

### Two more error rules from the contrast set

- **Declare non-support in the claim; reserve exceptions for what the claim cannot express.** Tika's
  `UnsupportedFormatException` javadoc: *"Whenever possible/convenient, it is better to distinguish file
  formats by mime so that unsupported formats will be handled by the `EmptyParser`."* An adapter that
  claims a host and then throws "no captions available" should have declared a narrower claim.
- **Validate remote payloads against a declarative schema at the boundary.** 122 of 135 streamlink
  plugins use `validate.Schema`, with `validate.any(success_shape, error_shape)` encoding "the source
  said no" *in the schema* rather than a downstream `try/except`. Because `ValidationError(ValueError)`
  and `streams()` catches `(OSError, ValueError)`, schema failure lands in the taxonomy automatically —
  no author has to remember to wrap anything. This is what catches silent field-shape drift that
  `data["a"]["b"][0]["url"]` turns into a plausible-looking wrong value.

## Fallback and disabled states

- **Ship a fallback that returns a well-formed empty result.** Tika's `EmptyParser` declares **zero**
  supported types and emits a valid empty XHTML document — no downstream null-handling, no dispatcher
  special case. Pygments' `TextLexer` is the epsilon-score variant (`priority = 0.01`, so `guess_lexer`
  never actually raises). yt-dlp's `GenericIE` is the "try harder" variant and carries the largest bug
  surface in the project.
- **Keep a registered-but-not-auto-dispatched state.** Universal convergence: FFmpeg
  `AVFMT_EXPERIMENTAL`, yt-dlp `_WORKING = False`, streamlink `NO_PRIORITY`, Tika `<parser-exclude>`.
  yt-dlp's is the most user-respectful — a broken adapter still *claims* the URL and emits *"The program
  functionality for this site has been marked as broken, and will probably not work"*
  (`YoutubeDL.py:1710-1712`) rather than silently falling through to a generic path and producing a
  confusing partial result.
