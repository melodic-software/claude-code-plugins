---
topic: extractor-architecture-prior-art
section: dispatch
abstract: URL-regex dispatch degrades into a hand-maintained host registry at scale; declarative host-keyed claims plus one CI collision test is the transferable shape, with an explicit trigger for adding priority later.
claims:
  - claim: "yt-dlp dispatches by iterating an ordered dict of extractors and taking the first whose suitable() returns true; there is no scoring and no explicit priority."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/YoutubeDL.py:1706-1725 (local checkout, yt-dlp @ 5d6b8c8)"
        tier: 0
        pool: "yt-dlp source"
      - url: "yt_dlp/extractor/common.py:616-632 (local checkout)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "Regex-on-URL dispatch does not scale cleanly: yt-dlp carries 74 suitable() overrides, 88 cross-extractor suitable() call sites, and 54 files whose _VALID_URL needs a negative lookahead."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "grep over yt_dlp/extractor/ at 5d6b8c8 — counts computed this turn"
        tier: 0
        pool: "yt-dlp source"
      - url: "yt_dlp/extractor/youtube/_video.py:1923, youtube/_tab.py:2204, :2494"
        tier: 0
        pool: "yt-dlp source"
  - claim: "No yt-dlp maintainer has publicly proposed replacing regex dispatch with a host registry; the repo has GitHub Discussions disabled, so no discussion corpus exists."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "gh api graphql repository(owner:yt-dlp,name:yt-dlp){hasDiscussionsEnabled} -> false"
        tier: 0
        pool: "GitHub API"
      - url: "gh search issues --repo yt-dlp/yt-dlp, seven phrasings, zero relevant hits"
        tier: 0
        pool: "GitHub API"
  - claim: "Streamlink migrated from an imperative can_handle_url() classmethod to declarative @pluginmatcher data specifically to enable a build-time static index, and shipped it."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/streamlink/streamlink/issues/3814"
        tier: 1
        pool: "streamlink maintainers"
      - url: "src/streamlink/session/plugins.py:146-169 (clone @ c3c2e98)"
        tier: 0
        pool: "streamlink source"
  - claim: "Scored dispatch is an upgrade forced by key collision, not by handler count; URL-host-keyed systems never made it."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "libavformat/format.c:191-230 (FFmpeg master)"
        tier: 0
        pool: "FFmpeg source"
      - url: "pygments/lexers/__init__.py:194-209, :292-301"
        tier: 0
        pool: "Pygments source"
      - url: "tika-core/.../mime/MimeTypes.java (Tika 3.3.2)"
        tier: 0
        pool: "Apache Tika source"
produced_by: phase-2-targeted-and-falsification
---

# Dispatch — bare URL to the right adapter

## Recommendation

**Declarative, host-keyed claims. No scoring, no numeric priority scale. One CI collision test.
Pattern matching only *within* a host an adapter already owns.**

## How yt-dlp actually dispatches — documented, Tier 0

`YoutubeDL.extract_info` (`yt_dlp/YoutubeDL.py:1706-1725`) is the whole mechanism:

```python
for key, ie in ies.items():
    if not ie.suitable(url):
        continue
    if not ie.working():
        self.report_warning('The program functionality for this site has been marked as broken, '
                            'and will probably not work.')
    ...
    return self.__extract_info(url, self.get_info_extractor(key), download, extra_info, process)
else:
    self.report_error(f'No suitable extractor{...} found for URL {url}')
```

- **First match wins** over an ordered dict. No scoring, no explicit priority, no ambiguity detection.
- **Ordering is the entire arbitration policy**, and the one ordering fact that matters is *asserted*
  rather than commented: `devscripts/make_lazy_extractors.py:84` —
  `assert ies[-1].__name__ == 'GenericIE', 'Last IE must be GenericIE'`, plus
  `assert b.__name__ != 'GenericIE', 'Cannot inherit from GenericIE'`. `extractor/extractors.py:29-30`
  explicitly re-sorts `GenericIE` to the tail.
- **No-match is a reported error, not an exception to the caller** — `report_error` with the traceback
  suppressed when `--use-extractors` restricted the set.
- **`suitable()` is a classmethod** (`common.py:627-632`) defaulting to
  `cls._match_valid_url(url) is not None`. `_VALID_URL` may be a single regex or a Sequence, compiled
  lazily and cached per-class via `cls.__dict__` (deliberately not `getattr`, so a subclass never
  inherits its parent's compiled pattern).

## Falsification: does regex dispatch beat a host→adapter registry?

**No. Verified by grep over my own checkout — Tier 0, counts computed this turn:**

| Measure | Count |
|---|---|
| `suitable()` overrides outside `common.py` | **74** |
| Call sites where one extractor calls **another extractor's** `suitable()` | **88** |
| Files whose `_VALID_URL` carries a negative lookahead `(?!` | **54** |
| Extractor modules | **940** |

The YouTube family implements precedence *in Python*, as a hand-maintained mutual-exclusion chain:

- `youtube/_video.py:1923` — `YoutubeIE.suitable()` returns `False` when `parse_qs(url)` has a `list`
  key. **It dispatches on the query string** — a dimension the URL regex does not model.
- `youtube/_tab.py:2204` — `YoutubeTabIE.suitable()` returns `False if YoutubeIE.suitable(url) else …`
- `youtube/_tab.py:2494` — `YoutubePlaylistIE.suitable()` returns `False if YoutubeTabIE.suitable(url)`

`YoutubeIE._VALID_URL` is ≈2.7 KB; `YoutubeTabIE` additionally needs a *conditional* regex group.

**Conclusion (inferred from the above, stated as inference):** regex-on-URL dispatch does not avoid a
host registry — it *becomes* one, written by hand, spread across 88 cross-class call sites, with
precedence invisible at every definition site. The thing regex buys over a host map is within-host
routing (which of this host's URL shapes is this?), and that is exactly where it should stay.

## The cost that forced a workaround, and the workaround that constrained the contract

PR #3234 (jordanlewis, 2022-03-28, closed in favour of `--use-extractors`), verbatim:

> This is important because each extractor typically needs to compile a regex, and all of that regex
> compilation adds up. In a profiler, this extractor initialization occupies **80% of startup time**
> on my test machine

`devscripts/make_lazy_extractors.py` exists to amortize that, hoisting exactly the dispatch surface
into a generated module — `STATIC_CLASS_PROPERTIES = ['IE_NAME','_ENABLED','_VALID_URL','_WORKING',
'IE_DESC','_NETRC_MACHINE','SEARCH_KEY','age_limit','_RETURN_TYPE']` and `CLASS_METHODS =
['ie_key','suitable','_match_valid_url','working','get_temp_id','_match_id',…]`.

**The performance workaround became a permanent constraint on the contract** (`common.py:630-631`):

> This function must import everything it needs (except other extractors), so that lazy_extractors
> works correctly

## Precedence was ultimately promoted to a runtime knob

`--force-generic-extractor` is deprecated in favour of `--use-extractors` / `--ies`
(commit `fe7866d0ed6bfa3904ce12b049a3424fdc0ea1fa`, pukkandan, 2022-08-24, *"Closes #3234, Closes
#2044"*). Per README:328-334 it lets users **name, regex-match, reorder, and negate** extractors at
runtime, including an `end` token to stop URL matching. Static ordering could not satisfy everyone.
Note the recursion: the selection mechanism is itself regex, over extractor *names*.

## The unanswerable case regex has no answer for

PR #1791 — *"Self-hosted extractors: Mastodon, PeerTube and Misskey"*, opened 2021-11-25, **still
open** (4½ years). You cannot tell from a URL whether an arbitrary domain runs PeerTube. pukkandan's
framing in #4307:

> Sometimes additional network requests are needed to check for a match. See #1791. If this is
> implemented into the normal flow of generic extraction, each unsupported URL will unnecessarily add
> these (potentially expensive) processing.

**gallery-dl solved exactly this case and yt-dlp did not** — see `RESEARCH-contrast-systems.md`,
`BaseExtractor.update()`: one class parameterized over a *data table* of instances, with the host list
compiled into the pattern at load time, a `basecategory:URL` escape prefix for unknown hosts, and
user-config-registered instances. That is the host-registry shape, and it exists in a peer system.

## What decides whether you need scoring

Convergent across the contrast set: **every scored system upgraded because its declarative key stopped
being unique** — `.m` (Matlab/ObjC/Mathematica), `.ttl` (Turtle/TeraTerm), `.asm` (Nasm/Tasm), `ftyp`
(MP4/JP2/JXL), ZIP and OLE2 containers, `application/xml`. The URL-keyed systems never upgraded,
because **a hostname is a unique key** — one host, one owner, one API surface.

**Deferred trigger, recorded with its precedent:** the moment an adapter's claim is *format*- or
*content*-shaped rather than host-shaped, keys collide and arbitration becomes mandatory. Streamlink's
canonical instance is `plugins/hls.py:16-23` — matcher `r"[^/]+/\S+\.m3u8(?:\?\S*)?"`, any host —
declared `LOW_PRIORITY` so all 134 site-specific plugins beat it without any of them knowing it exists.

## A collision detector beats a collision policy — two independent instances

- **gallery-dl**, `test/test_extractor.py`: for every registered class,
  `self.assertEqual(cls, extractor.find(cls.example).__class__)` — a **full-registry round-trip**, run
  over all 920 adapters. It is the only thing standing between first-match-wins and a silently
  shadowed adapter.
- **Tika**, `CompositeParser.findDuplicateParsers()` (TIKA-660) — ~20 lines, finds every media type
  more than one parser claims. A diagnostic, not a scoring rule.

Streamlink, by contrast, resolves equal-priority collisions **silently by iteration order** (strict
`>` in `session/plugins.py:146-155`) and has no such test. That is its weak spot, not a model.

## Second dispatch layer — content-based claiming

yt-dlp's strongest evidence that URL patterns alone are insufficient is PR #4307
(*"Generalized framework for webpage-based extraction"*, pukkandan, merged 2022-08-01). It shrank
`generic.py` from **4,189 → 1,303 lines** by inverting a dependency: GenericIE had been reaching into
**97** differently-named `_extract_url`/`_extract_urls` staticmethods across **107** extractor classes.
Motivation 4, verbatim:

> **The current method of extractor matching using only URL has it's limitations**
> * **a)** There are cases where url + webpage is needed for detection…
> * **b)** Sometimes additional network requests are needed to check for a match.

The contract text it produced (`common.py:540-550`) states the limitation in the spec itself and adds
an exclusive-claim signal: `_extract_from_webpage` may `raise self.StopExtraction` *"when the extractor
cannot reliably be matched using just the URL."*

**Cautionary detail:** embed-only extractors are declared by setting `_VALID_URL = False`
(`common.py:618-619`, `:4080`, `:4095`). The URL-dispatch field repurposed as a boolean opt-out is a
sentinel overload — what an untyped contract invites. If content claiming is in scope, make it a
separate declared capability.

**Anti-lesson from the same PR:** name-based reach-in across a plugin boundary is a trap. Brightcove
could not be migrated at all — *"because it's subclasses may depend on the signature of the current
functions."*

## Two-stage dispatch mechanics worth copying (from the contrast set)

1. **Every dispatch-relevant field lives in a cheap static index; the adapter module imports only after
   it wins.** Measured (Pygments 2.20.0, fresh interpreter): `get_lexer_by_name('python')` imports **2**
   lexer modules; `get_lexer_for_filename('x.m')` imports **22**; `guess_lexer(text)` imports **245**.
2. **The tie-break key must be in the cheap index.** Streamlink put `priority` in `_plugins.json`;
   Pygments left it on the class, which is precisely why ranking three `.m` candidates costs 22 imports.
3. **The generated index must be verified and must degrade to the slow path on mismatch.** Streamlink
   hashes `_plugins.json` against the wheel's `RECORD` and logs *"Plugins data checksum mismatch,
   falling back to loading all plugins"*; yt-dlp's `LazyLoadMetaClass.__getattr__` warns and resolves
   the real class. Cheapest local form: a CI check that regenerating the index is a no-op.
4. **Declarative hints may disambiguate content evidence; they must never overrule it.** Tika's
   `applyHint` lets a filename/`Content-Type` hint *select among* magic candidates or *specialize* one,
   never beat them (*"Hint didn't help, sorry"*), and explicitly ignores an interpreted type derived
   from an `http(s)` URL's name. FFmpeg does the opposite — `score += AVPROBE_SCORE_MIME_BONUS` (30) is
   unconditional and additive, so a server-supplied `Content-Type` alone clears `AVPROBE_SCORE_RETRY`
   (25) with no warning and no re-probe. A digest pipeline reads `Content-Type`, `og:video:type`, and
   filename extensions — all remotely controlled. Take Tika's posture. *(Exploitability of the FFmpeg
   path is **inferred** from the arithmetic; no filed CVE was found.)*
