---
topic: js-adapter-contract-design
section: dispatch
abstract: "Mature systems layer both models — classify input to a key, then look up an enumerated registry; yt-dlp's ordering is incidental rather than declared, and the repo's interpolated-import dispatch is simultaneously a type-safety and a path-traversal defect that one change fixes."
claims:
  - claim: "yt-dlp runs a registry OF predicates: get_info_extractor(name) is a dict lookup and ie_key is carried downstream, so the predicate scan runs once at the boundary and is never re-run after classification."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/YoutubeDL.py#L933-L944"
        tier: 1
        pool: "yt-dlp"
  - claim: "yt-dlp's match ordering is INCIDENTAL, not declared: the shipped lazy build and eager build differ at 1662 of 1751 positions, with only 'GenericIE last' preserved by an explicit assert."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/devscripts/make_lazy_extractors.py#L80-L98"
        tier: 1
        pool: "yt-dlp"
      - url: "local: pinned checkout 5d6b8c8 cloned and both orderings computed (Python 3.14.6)"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "First-match-wins is paid for with ~70 hand-written suitable() overrides returning False to defer to a named sibling — manual mutual exclusion whose purpose is making order irrelevant, with no test guarding it."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/CONTRIBUTING.md#L285"
        tier: 1
        pool: "yt-dlp"
      - url: "local: 52 extractor files overriding suitable() counted in the pinned checkout"
        tier: 0
        pool: "first-party empirical (this machine)"
  - claim: "No surveyed exhibit hard-errors on multiple matches; webpack's oneOf is a counter-precedent, existing to MAKE first-match-wins available rather than to forbid ambiguity."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://webpack.js.org/configuration/module/#ruleoneof"
        tier: 1
        pool: "webpack"
      - url: "https://mimesniff.spec.whatwg.org/"
        tier: 1
        pool: "WHATWG"
  - claim: "The interpolated dispatch is exploitable: platform='../secret/pwned' loads a module outside adapters/ while existsSync returns true; the usual path.resolve guard still passes for %2e-encoded variants because existsSync takes a filesystem path and import() takes a URL specifier."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://cwe.mitre.org/data/definitions/829.html"
        tier: 1
        pool: "MITRE CWE"
      - url: "https://cwe.mitre.org/data/definitions/22.html"
        tier: 1
        pool: "MITRE CWE"
      - url: "local probe: Node v24.18.0/win32, escape and guard-bypass both reproduced"
        tier: 0
        pool: "first-party empirical (this machine)"
produced_by: lane-c
---

# (c) Dispatch — how the pipeline picks WHICH adapter handles an input

Scope: plain ESM JavaScript, Node 24, small adapter set (2–3 today). Question: **static registry map
(key → adapter)** vs **per-adapter match predicate over the input**, judged on ambiguity, ordering,
and fail-closed behaviour on unknown input.

Confidence markers: **VERIFIED** (quoted from official text, or reproduced on this machine) /
**UNVERIFIED** / **REFUTED**.

**Empirical provenance.** yt-dlp claims are anchored to a pinned checkout:
commit **`5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc`** (committed 2026-08-04T22:58:34Z),
<https://github.com/yt-dlp/yt-dlp/tree/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc>. Every `file:line`
below was re-confirmed against that checkout. Ordering results marked *(probe)* were produced by
importing yt-dlp on this machine under **Python 3.14.6**; Node results under **Node v24.18.0**,
platform **win32**. Probe sources live in the session scratchpad (`scratchpad/ytdlp-repo`,
`scratchpad/esmprobe`) and are disposable.

---

## Executive answer

| | Static registry (key → adapter) | Match predicate per adapter |
|---|---|---|
| Ambiguity | **impossible by construction** (map keys are unique) | possible; must be *detected* or *prevented* |
| Ordering | irrelevant — no scan | load-bearing, and usually **incidental** unless declared |
| Fail-closed | free — key miss is a miss | needs an explicit terminator, else falls off the end |
| What it can't do | derive the key from a raw URL | — |

The finding that decides the design: **yt-dlp has BOTH, and they are the same object.**
`YoutubeDL._ies` is a name-keyed dict that doubles as the ordered match chain. The registry is used
for *addressing* an adapter you already named; the predicate scan is used for *classifying* a URL you
haven't. They are not alternatives — the mature system runs a **registry of predicates**.

The second finding: yt-dlp's chain order is **INCIDENTAL** (codepoint-sorted class names, plus two
hardcoded interventions), and it is not even stable between yt-dlp's two build modes — so its ~70
hand-written `suitable()` deferrals exist precisely *because* order cannot be trusted.

---

# PART 1 — PRIMARY EXHIBIT: yt-dlp's extractor system

## 1.1 `_VALID_URL`, `_match_valid_url`, `_VALID_URL_RE`, `suitable()`

**VERIFIED** —
[`yt_dlp/extractor/common.py:617-633`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/common.py#L617-L633):

```python
@classmethod
def _match_valid_url(cls, url):
    if cls._VALID_URL is False:
        return None
    # This does not use has/getattr intentionally - we want to know whether
    # we have cached the regexp for *this* class, whereas getattr would also
    # match the superclass
    if '_VALID_URL_RE' not in cls.__dict__:
        cls._VALID_URL_RE = tuple(map(re.compile, variadic(cls._VALID_URL)))
    return next(filter(None, (regex.match(url) for regex in cls._VALID_URL_RE)), None)

@classmethod
def suitable(cls, url):
    """Receives a URL and returns True if suitable for this IE."""
    # This function must import everything it needs (except other extractors),
    # so that lazy_extractors works correctly
    return cls._match_valid_url(url) is not None
```

Point by point, all **VERIFIED** from that source:

- **`_VALID_URL`** is a class attribute holding a regex string — or, via `variadic()`, a *sequence* of
  regex strings. Default is `None` (`common.py:592`). The sentinel **`_VALID_URL = False` means "never
  matches"** — an explicit opt-out from URL dispatch, distinct from `None`.
- **`_VALID_URL_RE`** is the compiled cache: a **tuple** of compiled patterns, memoised onto the class
  the first time `_match_valid_url` runs. The `'_VALID_URL_RE' not in cls.__dict__` check (rather than
  `hasattr`) is deliberate and commented: it forces **each subclass to compile its own** regex instead
  of silently inheriting the parent's compiled tuple. This is a real correctness trap in any
  inheritance-based adapter hierarchy.
- Matching uses **`regex.match`**, not `fullmatch` — anchored at the start only. A `_VALID_URL` that
  doesn't end with `$` will match any URL with the right *prefix*. This is the mechanical root of
  most shadowing between site-specific and broader extractors.
- **`suitable()`** is a `classmethod` whose default implementation is exactly
  `cls._match_valid_url(url) is not None`. It is the dispatch predicate; `_VALID_URL` is merely its
  default data. The docstring comment ("must import everything it needs") exists because `suitable`
  is one of the methods **copied verbatim into the generated lazy-extractor stubs** — see §1.3.
- Derived helpers on the same predicate: `_match_id` (`common.py:635`) pulls the named group `id` out
  of the match; `get_temp_id` (`common.py:639`) is its exception-swallowing form, used for the
  download archive before an extractor is even instantiated.

**`suitable()` is overridden when regex alone cannot express the boundary between sibling
extractors** — see §1.5, which is the interesting part.

## 1.2 The matching loop — first match wins

**VERIFIED** —
[`yt_dlp/YoutubeDL.py:1700-1725`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/YoutubeDL.py#L1700-L1725):

```python
if ie_key:
    ies = {ie_key: self._ies[ie_key]} if ie_key in self._ies else {}
else:
    ies = self._ies

for key, ie in ies.items():
    if not ie.suitable(url):
        continue

    if not ie.working():
        self.report_warning('The program functionality for this site has been marked as broken, '
                            'and will probably not work.')
    ...
    return self.__extract_info(url, self.get_info_extractor(key), download, extra_info, process)
else:
    extractors_restricted = self.params.get('allowed_extractors') not in (None, ['default'])
    self.report_error(f'No suitable extractor{format_field(ie_key, None, " (%s)")} found for URL {url}',
                      tb=False if extractors_restricted else None)
```

- **First match wins, unconditionally.** The loop `return`s on the first `suitable()` truthy. There is
  no scoring, no "collect all matches", no specificity comparison. **VERIFIED.**
- The docstring on `gen_extractor_classes` states the contract in the project's own words —
  [`yt_dlp/extractor/__init__.py:17-21`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/__init__.py#L17-L21):
  > `""" Return a list of supported extractors.`
  > `The order does matter; the first extractor matched is the one handling the URL.`
  > `"""`
  **VERIFIED.**
- **`_ies` is simultaneously the registry and the chain.** `self._ies = {}` (`YoutubeDL.py:643`) is a
  dict keyed by `ie_key()`; the loop iterates it in **insertion order**. One data structure, two
  jobs. **VERIFIED.**
- **`_WORKING` does NOT participate in dispatch.** *(Correcting a natural assumption.)* At
  `YoutubeDL.py:1710`, a non-working extractor **warns and proceeds** — it still claims the URL and
  still runs. `_WORKING` is a user-facing health flag (`working()` at `common.py:646`), not a filter.
  **VERIFIED.**
- **`_ENABLED` DOES act as a filter**, but only at chain-construction time — see §1.6.

## 1.3 How the list is ordered — INCIDENTAL, not declared

**This is the crux, and the answer is: incidental.** Three independent confirmations.

### (a) `_extractors.py` import order is NOT the match order — REFUTED premise

`yt_dlp/extractor/_extractors.py` is a flat, alphabetically-grouped import manifest (2474 lines at the
pin). `GenericIE` is imported at **line 653** — under `g`, roughly a quarter of the way in — not last.
**VERIFIED (probe).** CONTRIBUTING.md's only instruction about it is clerical
([CONTRIBUTING.md:285](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/CONTRIBUTING.md#L285)):

> "Add an import in `yt_dlp/extractor/_extractors.py`. Note that the class name must end with `IE`.
> Also note that when adding a parenthesized import group, the last import in the group must have a
> trailing comma in order for this formatting to be respected by our code formatter."

Nothing about position, priority, or ordering. So the premise "`_extractors.py` import order" defines
matching precedence is **REFUTED**.

### (b) The order is imposed in `extractors.py` from `dir()`

**VERIFIED** —
[`yt_dlp/extractor/extractors.py:18-32`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/extractors.py#L18-L32):

```python
if not _CLASS_LOOKUP:
    from . import _extractors

    members = tuple(
        (name, getattr(_extractors, name))
        for name in dir(_extractors)
        if name.endswith('IE'))
    _CLASS_LOOKUP = dict(itertools.chain(
        # Add Youtube first to improve matching performance
        ((name, value) for name, value in members if '.youtube' in value.__module__),
        # Add Generic last so that it is the fallback
        ((name, value) for name, value in members if name != 'GenericIE'),
        (('GenericIE', _extractors.GenericIE),),
    ))
```

Read that literally: the ordering is `dir()`'s output (i.e. **sorted attribute names**) with exactly
**two hardcoded interventions** — a YouTube block hoisted to the front *for performance*, and
`GenericIE` pinned to the back *as the fallback*. Everything between is alphabetical accident.

Empirical confirmation *(probe, Python 3.14.6, `YTDLP_NO_LAZY_EXTRACTORS=1 YTDLP_NO_PLUGINS=true`)*:

```
COUNT 1751
FIRST12  ['YoutubeClipIE','YoutubeConsentRedirectIE','YoutubeFavouritesIE','YoutubeHistoryIE',
          'YoutubeIE','YoutubeLivestreamEmbedIE', ...]
LAST4    ['ZoomClipsIE','ZoomIE','ZypeIE','GenericIE']
N_youtube_module 20 ; head == sorted(youtube members)  -> True
mid sorted by codepoint  -> True
mid sorted case-insensitively -> False        # 'ABCIE' precedes 'ABCIViewIE'
GenericIE index 1750 of 1751
```

**VERIFIED (probe).** Note it is **codepoint** order, not human alphabetical — `ABCOTVSClipsIE`
precedes `ABCOTVSIE` because `C` < `I`. Nobody chose that. It is the definition of incidental.

Also note **`YoutubeIE` sits at index 4**, *after* `YoutubeClipIE`/`YoutubeConsentRedirectIE`/
`YoutubeFavouritesIE`/`YoutubeHistoryIE`, and `YoutubeTabIE` at index 14 — so even inside the
deliberately-hoisted YouTube block, the relative priority of the two extractors that genuinely
contend for `youtube.com/...` URLs is alphabetical accident. Their actual precedence comes entirely
from `suitable()` overrides (§1.5). **VERIFIED (probe).**

### (c) The shipped order differs from the source order — the decisive proof

yt-dlp ships a build-generated `lazy_extractors.py` so the CLI doesn't import 941 extractor modules at
startup. Its `_CLASS_LOOKUP` is produced by `sort_ies()` in
[`devscripts/make_lazy_extractors.py:80-98`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/devscripts/make_lazy_extractors.py#L80-L98),
which **topologically hoists base classes ahead of their subclasses** so the generated stubs can be
defined in order.

I generated it and diffed the two orders *(probe)*:

```
same length True ; same set True
IDENTICAL ORDER? False
n_positions_differing 1662   (of 1751)
```

**1662 of 1751 positions differ between the two builds of the same program.** **VERIFIED (probe).**

And it is not a harmless permutation. A genuinely contending pair **flips**:

| class | eager order index | lazy (shipped) order index |
|---|---|---|
| `BandcampIE` | 134 | **128** |
| `BandcampAlbumIE` | 133 | **129** |

`BandcampAlbumIE` precedes `BandcampIE` in one build and follows it in the other. **VERIFIED (probe).**

The **only** ordering invariant that survives both builds is `GenericIE` last — and it survives
because it is *asserted*, at
[`make_lazy_extractors.py:84`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/devscripts/make_lazy_extractors.py#L84):

```python
assert ies[-1].__name__ == 'GenericIE', 'Last IE must be GenericIE'
```

(plus, at line 91, `assert b.__name__ != 'GenericIE', 'Cannot inherit from GenericIE'`).

**Verdict: yt-dlp's extractor order is INCIDENTAL. The single declared, enforced ordering fact in the
whole system is "GenericIE is last," and it is enforced by a build-time assertion rather than by the
list's shape.** Everything else that looks like precedence is either alphabetical accident or a
hand-written `suitable()` deferral.

### (d) The one place order IS declared: the user's `--use-extractors`

**VERIFIED** —
[README.md:328-334](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/README.md#L328-L334):

> `--use-extractors NAMES  Extractor names to use separated by commas. You can also use regexes,`
> `"all", "default" and "end" (end URL matching); e.g. --ies "holodex.*,end,youtube". Prefix the name`
> `with a "-" to exclude it, e.g. --ies default,-generic. Use --list-extractors for a list of`
> `extractor names. (Alias: --ies)`

The example is self-documenting: `holodex.*` runs first, `end` terminates matching, and `youtube`
after `end` is unreachable. **VERIFIED.** So yt-dlp's
*only* declared ordering surface is the one the **user** writes, overriding the incidental default.
Structurally the same move as Vite's `enforce` buckets (§2.1).

**A precision note on `--force-generic-extractor`, since it is easy to miscite.** README.md:2410
lists it under "Not recommended" as equivalent to `--ies generic,default`. The **live code path is
not that**: `YoutubeDL.py:1698-1702` does `ie_key = 'Generic'` and then
`ies = {ie_key: self._ies[ie_key]} if ie_key in self._ies else {}` — i.e. it **restricts dispatch to
that single extractor by key**, it does not reorder a chain. **VERIFIED.** So the reachable behaviour
is a pure keyed lookup that bypasses matching entirely — which is a *better* citation than the
deprecation table for the §3.3 recommendation (a catch-all registered under a key and reachable only
when asked for).

## 1.4 `GenericIE` — a fail-OPEN catch-all, and what it costs

**VERIFIED** —
[`yt_dlp/extractor/generic.py:53-56`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/generic.py#L53-L56):

```python
class GenericIE(InfoExtractor):
    IE_DESC = 'Generic downloader that works on some sites'
    _VALID_URL = r'.*'
    IE_NAME = 'generic'
```

`_VALID_URL = r'.*'` — it matches **every** input. Placed last (asserted, §1.3c), it is a total
function on URLs: **the predicate chain never fails to match.** That is fail-open by definition, and
worth naming plainly: *any* dispatch design that ends in a `.*` adapter has replaced "no adapter
matched" with "the catch-all matched," and the failure that used to be a dispatch error is now a
runtime error deep inside a different adapter.

**But GenericIE is a real adapter, not an error path.** It downloads the response and genuinely tries:
direct media links, M3U8/`#EXTM3U` playlists, DASH/ISM manifests, `<video>`/`<embed>`/`<object>`
scraping, and a long registry of embed extractors (`_extract_embeds`, `generic.py:986+`). It reports
what it detects (`self.report_detected('M3U playlist')`). It has genuine independent value — many
sites work *only* through it.

**And even it is fail-closed at the outcome level.** When best-effort finds nothing —
[`generic.py:984`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/generic.py#L984):

```python
raise UnsupportedError(url)
```

So the catch-all **defers** the error; it does not remove it. **VERIFIED.**

### The exact exception

**VERIFIED** —
[`yt_dlp/utils/_utils.py:1025-1029`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/utils/_utils.py#L1025-L1029):

```python
class UnsupportedError(ExtractorError):
    def __init__(self, url):
        super().__init__(
            f'Unsupported URL: {url}', expected=True)
        self.url = url
```

Exact message: **`Unsupported URL: <url>`**, `expected=True` (i.e. a user-facing condition, not a bug).

### The opt-in fail-CLOSED terminator

**VERIFIED** —
[`common.py:4170-4176`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/common.py#L4170-L4176):

```python
class UnsupportedURLIE(InfoExtractor):
    _VALID_URL = '.*'
    _ENABLED = False
    IE_DESC = False

    def _real_extract(self, url):
        raise UnsupportedError(url)
```

This is a **second** `.*` matcher whose entire body is "raise." It is registered under the hardcoded
alias `'end'` at [`YoutubeDL.py:934`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/YoutubeDL.py#L934)
(`all_ies['end'] = UnsupportedURLIE()` — a literal alias, *not* derived from `IE_NAME`), and
`_ENABLED = False` keeps it out of the default chain. It exists **only** so a user can write
`--ies "holodex.*,end"` and convert the whole system from fail-open to fail-closed. **VERIFIED.**

That is a notable design point for us: yt-dlp ships **both** a fail-open terminator (Generic, on by
default) and a fail-closed terminator (`end`, opt-in), and lets the *operator* choose which one
terminates the chain.

### And if neither terminator is reachable

If the chain is exhausted with no match (only possible when the user has restricted extractors), the
`for…else` at [`YoutubeDL.py:1723-1725`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/YoutubeDL.py#L1723-L1725)
emits **`No suitable extractor found for URL <url>`** (with `(<ie_key>)` interpolated when an explicit
key was requested). Note it calls `report_error`, i.e. it degrades rather than throwing. **VERIFIED.**

## 1.5 AMBIGUITY — no precedence rule; disjointness is hand-maintained

**Is there a documented precedence rule for two extractors whose `_VALID_URL` both match?**
**No. VERIFIED negative.** I grepped
[CONTRIBUTING.md](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/CONTRIBUTING.md)
for `suitable`, `order`, `Generic`, `precedence` — the only `_VALID_URL` guidance is about regex
*quality* (CONTRIBUTING.md:561-567: prefer `[^/]+` over over-escaped patterns), never about conflicts.
The sole statement of the rule anywhere in the repo is the `gen_extractor_classes` docstring quoted in
§1.2. There is **no** most-specific-wins, no scoring, no conflict detection, and no test that the
1751 `_VALID_URL` patterns are pairwise disjoint.

**So how is a site-specific extractor kept from being shadowed?** Three mechanisms, in ascending order
of how much yt-dlp actually relies on them:

1. **Regex specificity** — the ordinary case. Two extractors simply never both match, because the
   patterns are narrow. This is the 95% case and it is *unenforced*: nothing checks it.
2. **Ordering convention** — **essentially unused**, and per §1.3 unusable: the order is codepoint
   accident and flips between builds. The single exception is GenericIE-last.
3. **`suitable()` overrides that explicitly return `False` to defer to a named sibling** — the real
   mechanism. **52 extractor files override `suitable`; 70 of those override bodies contain a `False`
   deferral** *(probe: `grep -rn "def suitable" -A6 yt_dlp/extractor/ | grep -c False`)*. **VERIFIED.**

Real examples, all **VERIFIED** at the pin:

[`bandcamp.py:380-384`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/bandcamp.py#L380-L384) — `BandcampAlbumIE`:
```python
@classmethod
def suitable(cls, url):
    return (False
            if BandcampWeeklyIE.suitable(url) or BandcampIE.suitable(url)
            else super().suitable(url))
```

[`youtube/_tab.py:2203-2205`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/youtube/_tab.py#L2203-L2205) — `YoutubeTabIE`:
```python
@classmethod
def suitable(cls, url):
    return False if YoutubeIE.suitable(url) else super().suitable(url)
```

[`youtube/_video.py:1922-1929`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/youtube/_video.py#L1922-L1929) — `YoutubeIE`, deferring **back**:
```python
@classmethod
def suitable(cls, url):
    from yt_dlp.utils import parse_qs
    qs = parse_qs(url)
    if qs.get('list', [None])[0]:
        return False
    return super().suitable(url)
```

[`twitch.py:1017-1027`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/extractor/twitch.py#L1017-L1027) — a six-way exclusion:
```python
@classmethod
def suitable(cls, url):
    return (False
            if any(ie.suitable(url) for ie in (
                TwitchVodIE, TwitchCollectionIE, TwitchVideosIE,
                TwitchVideosClipsIE, TwitchVideosCollectionsIE, TwitchClipsIE))
            else super().suitable(url))
```

(Also `pornhub.py:758`, `nrk.py:621` and `nrk.py:716`, `bbc.py`, `bilibili.py`, `zdf.py`, and ~45 more.)

**Read what this actually is.** `YoutubeIE` ↔ `YoutubeTabIE` exclude each other **in both directions**
on complementary conditions (`?list=` present → Tab; else → Video). That is not a precedence rule —
it is **hand-written mutual exclusion that makes order irrelevant**. The authors are manually
restoring, per-pair, the disjointness that a registry would give for free. They are paying that cost
across 70 sites, forever, with no mechanism to verify it and no test that would catch a regression.

**Related knobs**, both **VERIFIED**:
- **`_WORKING`** — *not* a dispatch filter (§1.2). Warns, then extracts anyway.
- **`_ENABLED`** — is a filter, but only when building the chain:
  [`YoutubeDL.py:933-944`](https://github.com/yt-dlp/yt-dlp/blob/5d6b8c8cd19785c3086ae3a9ec618c45e25eb3bc/yt_dlp/YoutubeDL.py#L933-L944)
  computes `'default': [name for name, ie in all_ies.items() if ie._ENABLED]`. `_ENABLED = False`
  extractors (e.g. `UnsupportedURLIE`) are reachable only by being named in `--ies`.
- **`--use-extractors` / `--ies`** — user-declared order and set, with regex support, `-`-prefixed
  exclusion, and the `end` sentinel (§1.3d, §1.4).

## 1.6 YES — a static name-keyed registry exists ALONGSIDE the predicate

**This is the key finding.** All **VERIFIED**:

| surface | file:line | role |
|---|---|---|
| `IE_NAME` | `common.py:839-841` — `@classproperty` returning `cls.__name__[:-2]` | display / **selection** name; overridable |
| `ie_key()` | `common.py:835-838` — `"""A string for getting the InfoExtractor with get_info_extractor"""`, returns `cls.__name__[:-2]` | the **chain/registry key**; **not** affected by an `IE_NAME` override |
| `_CLASS_LOOKUP` | `extractors.py:24-32` | module-level `dict` name → class; the canonical class table |
| `get_info_extractor(ie_name)` | `__init__.py:47-50` — `return _extractors_context.value[f'{ie_name}IE']` | **direct dict lookup by name — no scanning, no predicates** |
| `YoutubeDL._ies` | `YoutubeDL.py:643`, `909-914` | per-session ordered dict, key = `ie_key()`; *both* registry and match chain |
| `YoutubeDL.get_info_extractor(ie_key)` | `YoutubeDL.py:917-926` | instance cache in front of the class registry |

*(Note: `_ALL_CLASSES` is the historical youtube-dl name; at this pin the structure is
`_CLASS_LOOKUP` plus the `globals.extractors` Indirect. **Premise partially REFUTED** — don't cite
`_ALL_CLASSES` for current yt-dlp.)*

**There are in fact TWO naming surfaces, not one — worth stating precisely.**
`add_default_info_extractors` builds its candidate table keyed by **`ie.IE_NAME.lower()`**
(`YoutubeDL.py:933`), which is the namespace `--ies` matches against; `add_info_extractor` then keys
the live `_ies` chain by **`ie.ie_key()`** (`YoutubeDL.py:912`). Those are different strings whenever
`IE_NAME` is overridden. Probe *(Python 3.14.6)*: `GenericIE.IE_NAME == 'generic'` but
`GenericIE.ie_key() == 'Generic'`; `UnsupportedURLIE.IE_NAME == 'UnsupportedURL'` while its chain
entry is registered under the hardcoded alias `'end'`. **VERIFIED (probe).** So the *selection*
namespace (user-facing, lowercased, regex-matched) and the *addressing* namespace (`ie_key`, used by
archive IDs, `url_result`, and `get_info_extractor`) are deliberately distinct. A design lesson in
itself: the key an operator types and the key the system carries internally do not have to be — and
here are not — the same string.

**How the two coexist — the division of labour is clean:**

- **Registry by key** is used whenever the adapter's identity is **already known**: an explicit
  `ie_key=` on `extract_info` short-circuits the entire scan to a single dict lookup
  (`YoutubeDL.py:1701-1702`); the download archive stores `ie_key` and re-hydrates by name
  (`make_archive_id`); playlist entries carry `ie_key`/`extractor_key` forward so children never
  re-dispatch; `--ies` selects by name; `url_result(url, ie_key)` lets one extractor hand a URL to a
  *named* sibling without going through matching at all.
- **Predicate scan** is used only for the one job the registry cannot do: **classifying a raw URL
  whose adapter is unknown.**

The scan is the *entry point*; the registry is the *addressing system*. Crucially, once an adapter is
identified, yt-dlp **stops using predicates** and carries the key. Dispatch happens once, at the
boundary. Everything inside the system is key-addressed.

---

# PART 2 — SECOND EXHIBITS

## 2.1 Vite — declared coarse buckets instead of a global list

**VERIFIED** — <https://vite.dev/guide/api-plugin.html> ("Plugin Ordering"), verbatim:

> "A Vite plugin can additionally specify an `enforce` property (similar to webpack loaders) to adjust
> its application order. The value of `enforce` can be either `"pre"` or `"post"`. The resolved plugins
> will be in the following order:
>
> - Alias
> - User plugins with `enforce: 'pre'`
> - Vite core plugins
> - User plugins without enforce value
> - Vite build plugins
> - User plugins with `enforce: 'post'`
> - Vite post build plugins (minify, manifest, reporting)
>
> Note that this is separate from hooks ordering, those are still separately subject to their `order`
> attribute as usual for Rolldown hooks."

**VERIFIED** — same page, "Conditional Application":

> "By default plugins are invoked for both serve and build. In cases where a plugin needs to be
> conditionally applied only during serve or build, use the `apply` property to only invoke them
> during `'build'` or `'serve'`"

with `apply: 'build', // or 'serve'` and the function form:

```js
apply(config, { command }) {
  // apply only on build but not for SSR
  return command === 'build' && !config.build.ssr
}
```

**UNVERIFIED (documented negative):** the Vite docs do **not** state that plugins within a bucket run
in `plugins`-array order. Probes of the page for "array order", "in the order", "applied in order"
found nothing. The closest doc support is Rollup's, not Vite's —
<https://rollupjs.org/plugin-development/>:

> "`order: "pre" | "post" | null` If there are several plugins implementing this hook, either run this
> plugin first (`"pre"`), last (`"post"`), or in the user-specified position (no value or `null`)."

**The lesson for us.** Vite has hundreds of third-party plugins and **no global hand-maintained
ordering list**. Instead each plugin **declares** one of three coarse buckets, and the framework
publishes the bucket sequence. Two properties follow: (a) a plugin author states a *relative
intention* (`pre`/`post`) without knowing any other plugin's name; (b) the ordering is **declared and
documented**, so it is reviewable — the exact opposite of yt-dlp's codepoint accident. `apply` is the
same idea for *applicability*: a declared coarse condition (`build`/`serve`), escalating to a
predicate function only when the coarse label is insufficient. **A declared enum first, a predicate
only where the enum runs out** is a reusable shape.

## 2.2 Webpack — `oneOf` is explicitly first-match-wins

**VERIFIED** — <https://webpack.js.org/configuration/module/> ("Rule.oneOf"), the section's complete
prose, verbatim:

> "An array of `Rules` from which only the first matching Rule is used when the Rule matches."

**VERIFIED** — same page, "Nested rules":

> "Nested rules can be specified under the properties `rules` and `oneOf`. These rules are evaluated
> only when the parent Rule condition matches. Each nested rule can contain its own conditions. The
> order of evaluation is as follows: 1. The parent rule 2. `rules` 3. `oneOf`"

**VERIFIED** — same page, conditions:

> "**Rule.test** — Include all modules that pass test assertion. If you supply a `Rule.test` option,
> you cannot also supply a `Rule.resource`."
> "**Rule.include** — Include all modules matching any of these conditions. If you supply a
> `Rule.include` option, you cannot also supply a `Rule.resource`."
> "**Rule.resource** — A `Condition` matched with the resource."
> "In a Rule the properties `test`, `include`, `exclude` and `resource` are matched with the resource
> and the property `issuer` is matched with the issuer."
> "**When using multiple conditions, all conditions must match.**"

**VERIFIED negative:** webpack's docs do **not** state what happens by default when several
*top-level* `module.rules` match the same module. Case-insensitive probes for "all rules",
"matching rules", "multiple rules", "rules are applied" found no such statement. The behaviour is
implied by "Rule results are used only when the Rule condition matches" plus "**Rule.parser** — All
applied parser options are merged" — i.e. all matching rules compose — but webpack never says it.
Mark as **UNVERIFIED**.

**VERIFIED** — separate declared-order mechanisms on the same page/site:
`Rule.use`: *"Loaders can be chained by passing multiple loaders, which will be applied from right to
left (last to first configured)."* <https://webpack.js.org/concepts/loaders/>: *"Loaders are
evaluated/executed from right to left (or from bottom to top)."* And `Rule.enforce` (`'pre' | 'post'`)
— webpack's own bucket mechanism, which Vite's `enforce` is explicitly modelled on.

**Honest read for our question:** `oneOf` is a **counter**-precedent to hard-erroring on multiple
matches. Webpack's *default* is "all matching rules compose"; `oneOf` is the **opt-in** to
first-match-wins, chosen when the author wants exclusivity. So webpack's contribution is not "error on
ambiguity" but "**make the multi-match policy an explicit, named choice at the call site**" — the
config author writes `oneOf` and thereby *declares* that these alternatives are exclusive and ordered.

## 2.3 `HTMLMediaElement.canPlayType()` — a standardized GRADED predicate

**VERIFIED** — HTML Living Standard, <https://html.spec.whatwg.org/multipage/media.html#mime-types>
(page "Last Updated 11 August 2026"). The IDL:

> `enum CanPlayTypeResult { "" /* empty string */, "maybe", "probably" };`

The single normative paragraph defining the semantics, verbatim:

> "The `canPlayType(type)` method must return the empty string if *type* is a type that the user agent
> knows it cannot render or is the type "`application/octet-stream`"; it must return "`probably`" if
> the user agent is confident that the type represents a media resource that it can render if used
> with this `audio` or `video` element; and it must return "`maybe`" otherwise. Implementers are
> encouraged to return "`maybe`" unless the type can be confidently established as being supported or
> not. Generally, a user agent should never return "`probably`" for a type that allows the `codecs`
> parameter if that parameter is not present."

**"probably" is tied to the `codecs` parameter — VERIFIED**, at SHOULD strength ("Generally … should
never"), not MUST.

**Why three grades and not a boolean — PARTIALLY VERIFIED, with a correction.**
The spec **does not state a rationale for three values specifically**; there is no "why not a boolean"
note. Claiming one would be fabrication. What the spec *does* state is a rationale for **graded
confidence**, which motivates the `""` vs `{maybe, probably}` split — same section, verbatim:

> "Types are usually somewhat incomplete descriptions; for example "`video/mpeg`" doesn't say anything
> except what the container type is, and even a type like "`video/mp4; codecs="avc1.42E01E,
> mp4a.40.2"`" doesn't include information like the actual bitrate (only the maximum bitrate). Thus,
> given a type, a user agent can often only know whether it *might* be able to play media of that type
> (with varying levels of confidence), or whether it *definitely cannot* play media of that type."

and:

> "A type that the user agent knows it cannot render is one that describes a resource that the user
> agent definitely does not support, for example because it doesn't recognize the container type, or
> it doesn't support the listed codecs."

**Corrections to two premises**, both **REFUTED**: there is no definition *table or list* of the return
values in the spec (one IDL enum + one normative paragraph); and there is **no** spec note calling the
result advisory or non-guaranteed — the page contains zero occurrences of "advisory" or "guarantee".
The "not a promise" framing appears on **MDN**, not the spec —
<https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/canPlayType>, verbatim:

> "- `""` (empty string) — : The media cannot be played on the current device.
> - `probably` — : The media is probably playable on this device.
> - `maybe` — : There is not enough information to determine whether the media can play (until
>   playback is actually attempted)."

**The real lesson, which is not "use three grades".** The spec's own reasoning is that **the input is
an incomplete description of the resource**, so a truthful predicate cannot be total. The third grade
exists to let the implementation say *"I cannot decide from what you gave me."* The asymmetry is the
design: `""` is a **confident negative**, `probably` a **confident positive**, `maybe` an **explicit
abstention**. Whether *our* predicate needs three grades therefore reduces to one question: **is a URL
a complete description of which adapter owns it?** For a YouTube/Vimeo/local-file pipeline it very
nearly is — the host name is dispositive. So the graded form is not indicated for us; the *reason*
grades exist is, though — it tells you exactly when to reach for them (when the input under-determines
the answer, an adapter must be able to say "don't know" instead of guessing).

## 2.4 WHATWG MIME Sniffing — ordered table, first match wins

**VERIFIED** — <https://mimesniff.spec.whatwg.org/> (Living Standard, "Last Updated 17 July 2026").

Every table-driven matcher (§6.1 image, §6.2 audio/video, §6.3 font, §6.4 archive, §7.1 unknown type)
is the identical loop, verbatim:

> "Execute the following steps for each row *row* in the following table:
> - Let *patternMatched* be the result of the pattern matching algorithm given *input*, the value in
>   the first column of *row*, the value in the second column of *row*, and the value in the third
>   column of *row*.
> - If *patternMatched* is true, return the value in the fourth column of *row*.
>
> […table…]
>
> Return undefined."

And the top-level §7 algorithm is an ordered sequence of guarded branches each ending "Abort these
steps," so the earliest applicable branch decides:

> "1. If the supplied MIME type is an XML MIME type or HTML MIME type, the computed MIME type is the
> supplied MIME type. Abort these steps. … 7. The computed MIME type is the supplied MIME type."

**One paragraph answer:** the spec resolves "several patterns could match" **structurally rather than
by a stated rule** — it fixes a total order (table row order, then step order), returns on the first
match, and terminates with an explicit default (`return undefined` / "the computed MIME type is the
supplied MIME type"). There is **no** tie-break rule, **no** specificity metric, and — **VERIFIED
negative** — **zero occurrences of "ambigu\*" in the whole spec**, and no claim that the patterns are
mutually exclusive or that the table is ordered by specificity. That row order means sequential order
is an inference from Infra's `for each` (<https://infra.spec.whatwg.org/>: *"To iterate over a list,
performing a set of steps on each item **in order**…"*) rather than a sentence in mimesniff itself —
mark the *ordering-is-sequential* reading **inferred**, the *first-match-returns* control flow
**VERIFIED**.

Worth noting what mimesniff *does* say about why any of this is specified at all — §1:

> "Without a clear specification for how to "sniff" the MIME type, each user agent has been forced to
> reverse-engineer the algorithms of other user agents in order to maintain interoperability.
> Inevitably, these efforts have not been entirely successful, resulting in divergent behaviors among
> user agents. In some cases, these divergent behaviors have had security implications"

**That is the argument for making dispatch order explicit rather than emergent**, stated by a
standards body about exactly this class of problem: undeclared ordering is reverse-engineered,
diverges, and the divergence becomes a security bug.

## 2.5 ESLint flat config — later overrides earlier, on conflicts only

**VERIFIED** —
<https://eslint.org/docs/latest/use/configure/configuration-files#cascading-configuration-objects>,
section "Cascading Configuration Objects":

> "When more than one configuration object matches a given filename, the configuration objects are
> merged with later objects overriding previous objects when there is a conflict."

**Important qualifier, same section, verbatim** — do not cite the sentence above alone:

> "Using this configuration, all JavaScript files define a custom global object defined called
> `MY_CUSTOM_GLOBAL` while those JavaScript files in the `tests` directory have `it` and `describe`
> defined as global objects in addition to `MY_CUSTOM_GLOBAL`. For any JavaScript file in the `tests`
> directory, both configuration objects are applied, so `languageOptions.globals` are merged to create
> a final result."

So ESLint is **last-match-wins per conflicting key**, with additive merge otherwise — a *third*
multi-match policy, distinct from webpack's compose-all and yt-dlp's first-match-wins. (Disambiguation
trap: the same page's "Configuration File Precedence" section is about which config *file* wins, not
array order. Don't cite it.)

## 2.6 Chain of Responsibility (GoF, 1994) — receipt is not guaranteed

**VERIFIED as to wording; UNVERIFIED as to edition/printing/page.** Reached via the publisher-hosted
excerpt at <https://www.informit.com/articles/article.aspx?p=1398601> (InformIT is Pearson's imprint
site; Addison-Wesley is a Pearson imprint), bylined "By Erich Gamma, Richard Helm, Ralph Johnson,
John M. Vlissides" and self-described as an excerpt from *Design Patterns: Elements of Reusable
Object-Oriented Software*. The pattern's own **Consequences**, item 3, verbatim:

> "***Receipt isn't guaranteed.*** Since a request has no explicit receiver, there's no *guarantee*
> it'll be handled—the request can fall off the end of the chain without ever being handled. A request
> can also go unhandled when the chain is not configured properly."

Its stated benefits, for balance:

> "***Reduced coupling.*** The pattern frees an object from knowing which other object handles a
> request. An object only has to know that a request will be handled "appropriately." … ***Added
> flexibility in assigning responsibilities to objects.*** … You can add or change responsibilities
> for handling a request by adding to or otherwise changing the chain at run-time."

**No page number is cited because none could be verified. Do not invent one.** The reached page states
only title and authors — it does not state "1994", "Addison-Wesley", or an edition; that provenance is
from the request, not from this source, and remains **UNVERIFIED**.

**This is the fail-open/fail-closed question stated by the pattern's own authors, 32 years ago.** A
predicate chain *is* Chain of Responsibility. Its documented liability is exactly ours: the request
falls off the end. And note the second sentence — "a request can also go unhandled when the chain is
not configured properly" — which is precisely yt-dlp's `--ies "holodex.*,end,youtube"` footgun and
precisely what incidental ordering produces.

---

# PART 3 — THE FOUR ANSWERS

## 3.1 Which model do mature systems converge on at small N? Where is the crossover?

**They converge on both, layered — and the layering is the answer, not a compromise.**

The invariant across every exhibit: **a key-addressed registry is always present; a predicate scan is
added only where the key is not derivable from the input.** yt-dlp is the clearest case —
`get_info_extractor(name)` is a bare dict lookup (`__init__.py:47-50`) and the `_ies` scan exists
solely for the one operation the dict cannot do: turn an unclassified URL into a name. Once
classified, yt-dlp carries `ie_key` everywhere (archive IDs, playlist entries, `url_result`) and never
re-runs a predicate. **VERIFIED, §1.6.**

For a URL input, that means the honest decomposition is:

1. **Classify** URL → key. A pure, testable, side-effect-free function.
2. **Look up** key → adapter, in an enumerated static map (`{ youtube: () => import('./youtube.js') }`).
3. **Everything downstream carries the key**, never the URL-plus-guess.

That decomposition gives the TypeScript-checkability the sibling research established for enumerated
registries (a `() => import(...)` thunk map keeps static types; an interpolated specifier does not),
while still accepting a raw URL at the boundary. **The two candidate models are not competitors: (ii)
is the classifier, (i) is the registry, and you want both.**

**Does the answer change with N? Yes, but not in the direction people expect — and the crossover is
not a count.** The crossover is **who owns the adapters**:

- **Closed set, one owner** (our case): the classifier can be **one function** the host owns —
  literally a `switch` on `URL.hostname`, or a table of `{ key, test }` the host holds. No per-adapter
  predicate needed at all. The adapter exports its capability, not its claim on the input. This is
  cheaper, is checkable in one place, and makes disjointness a *local, readable* property.
- **Open set, independent contributors** (yt-dlp: 1751 extractors, 941 files): a central classifier
  becomes an unmergeable bottleneck — every new site would edit the same function. The predicate
  *must* move into the adapter, and dispatch necessarily becomes a scan. That is the crossover, and
  it is a **governance** boundary, not a numeric one. It fires the moment adapters are contributed
  by people who cannot edit the host's classifier — realistically, third-party plugins.

At N=3, host-owned classification. Adopting predicate-in-adapter early buys nothing and imports
yt-dlp's whole disjointness-maintenance tax. If third-party adapters are later in scope, the migration
is additive and cheap: keep the registry, let an adapter optionally export a predicate, and have the
host's classifier consult registered predicates *after* its own table — i.e. exactly Vite's shape,
where a declared coarse bucket handles the common case and a function handles the rest (§2.1).

## 3.2 AMBIGUITY: what do the exhibits do, and what should we do?

**Five distinct policies are in evidence, and no two exhibits agree:**

| exhibit | policy on multiple matches | declared or incidental order |
|---|---|---|
| yt-dlp | first match wins | **incidental** (codepoint; flips between builds) |
| webpack `oneOf` | first match wins | **declared** (array order), opt-in per call site |
| webpack default `module.rules` | all matching compose | declared (array), but policy **undocumented** |
| ESLint flat config | later wins, per conflicting key; else merge | **declared** (array order) |
| mimesniff | first match wins, then explicit default | **declared** (spec table order) |
| `canPlayType` | graded confidence; caller decides | n/a |
| GoF CoR | first handler that accepts; may fall off the end | declared (chain construction) |

**Nobody hard-errors on multiple matches. That is an honest negative — I found no precedent for it in
these exhibits.** Do not claim otherwise; in particular `oneOf` is a *counter*-precedent, since it
exists to make first-match-wins available, not to forbid ambiguity.

But the exhibits do supply the argument for it, from the opposite direction:

- **yt-dlp's ~70 hand-written `suitable()` deferrals are the cost of not detecting ambiguity.**
  (§1.5, VERIFIED.) The authors evidently *want* disjointness — `YoutubeIE`/`YoutubeTabIE` exclude each
  other in both directions, which is the definition of "we do not want order to decide this." They
  have no mechanism to check it, so they encode it by hand, per pair, permanently. That is 70 sites
  of manual work standing in for one assertion.
- **mimesniff's own introduction** says undeclared, reverse-engineered matching behaviour "resulted in
  divergent behaviors among user agents" with "security implications" (§2.4, VERIFIED).
- **GoF names the liability directly**: receipt isn't guaranteed, and a request goes unhandled "when
  the chain is not configured properly" (§2.6, VERIFIED).
- **Every declared-order exhibit puts the order in a place a human reads** — a config array, a spec
  table, a documented bucket list. Not one of them derives order from a filename or an identifier's
  codepoints.

**Recommendation for a system valuing correctness over convenience at N=3: evaluate ALL predicates and
throw on >1 match.** The reasoning, stated as tradeoffs rather than assertions:

- **Cost is provably negligible at small N.** Three regexes vs one is not a measurable cost on a
  per-video pipeline. (yt-dlp's opposite choice is well-founded *for yt-dlp* — its own source comment
  "Add Youtube first to improve matching performance" (`extractors.py:26`) shows that at N=1751 the
  scan is a real cost, which is exactly why it returns on first match. **That justification does not
  transfer to N=3.**)
- **It converts a silent-wrong-adapter bug into a loud one.** With first-match-wins, an overlapping
  pattern produces a *plausible but wrong* result — the failure surfaces later, somewhere else, as
  bad output rather than as a dispatch error. With ambiguity-is-an-error, it surfaces at the boundary
  with both claimants named.
- **It is a strictly stronger invariant than the one yt-dlp maintains by hand**, obtained
  automatically. If ambiguity never legitimately occurs, the check never fires and costs nothing; the
  first time it fires, it has caught a real defect.
- **It removes the need to have an ordering opinion at all** — which matters given §1.3's
  demonstration that an order nobody declared can silently invert between builds of the same program.
- **The honest cost:** it forbids the deliberate specific-then-general layering that first-match-wins
  gives for free. At N=3 with distinct hosts, that is not a capability we need. If we ever do, the
  escape hatch is `oneOf`'s shape: make exclusivity an **explicit, named** declaration at the call
  site rather than an emergent property of list order.
- **Cheaper still, and complementary:** disjointness at N=3 is *testable*. A conformance test that
  runs every adapter's predicate over a corpus of fixture URLs and asserts exactly one match per URL
  gives most of the benefit at build time. Do both — the test catches it in CI, the runtime check
  catches what the corpus missed.

## 3.3 FAIL-CLOSED on unknown input, concretely

**Steelman for yt-dlp's fail-open `GenericIE`, taken seriously:**

1. **The catch-all is a genuine adapter, not an error path.** `GenericIE` really extracts: direct
   media URLs, `#EXTM3U` playlists, DASH/ISM manifests, `<video>`/`<embed>` scraping, and a large
   embed registry. It reports what it detected. Many sites are supported *only* through it. Refusing
   unknown URLs would delete real capability. (§1.4, VERIFIED.)
2. **The problem domain is genuinely open.** There are more video sites than extractors and always
   will be. The catch-all is how a URL nobody has written an extractor for still works today.
3. **It preserves a fast path to contribution.** Generic working on a site is the signal that a
   dedicated extractor is worth writing.
4. **It is still fail-closed at the outcome.** `GenericIE` raises `UnsupportedError` —
   `Unsupported URL: <url>` — when best-effort finds nothing (`generic.py:984`, VERIFIED). The
   catch-all **defers** the error to where more information is available; it does not swallow it.
5. **yt-dlp lets the operator opt out.** `UnsupportedURLIE` registered as `end` turns the chain
   fail-closed on demand (§1.4, VERIFIED). Fail-open is a *default*, not a doctrine.

**When that steelman applies — all four conditions, jointly:**
(a) the input domain is genuinely open-ended; (b) a real, useful best-effort implementation exists;
(c) that implementation can *itself* detect failure and raise; (d) mis-handling is cheap and visible
(a download fails; nothing is corrupted).

**Whether our case has such a thing.** Ask concretely: is there a best-effort adapter that, given an
arbitrary URL, produces a *correct* transcript/digest — a generic "fetch the page, find a media
element, pull captions" adapter that genuinely works? If such an adapter exists and is worth
building, it belongs in the registry **as a named adapter the caller can request** — not as a `.*`
terminator that silently absorbs typos, unsupported hosts, and misrouted inputs. Note what condition
(d) means for a *digest* pipeline specifically: a wrong-adapter failure does not fail loudly, it
produces a **plausible-looking wrong digest** — the visibility premise of the steelman does not hold.
Until such an adapter demonstrably exists, condition (b) fails and the steelman does not apply.

**So: fail closed, concretely.**

- Unknown key ⇒ **throw**, with a typed error carrying the input and the enumerated set of known keys.
  This is free with a registry: a key miss *is* a miss (`Object.hasOwn(registry, key)`), no terminator
  entry required.
- Name the exception and fix its message, following `UnsupportedError`'s example of a stable,
  greppable, user-facing string that names the offending input. yt-dlp's `Unsupported URL: <url>`
  (VERIFIED, `_utils.py:1027-1028`) is a good model.
- If a generic adapter is ever added, register it **under a key** (`generic`), reachable only when the
  caller asks for it. yt-dlp's `force_generic_extractor` does exactly this in code —
  `ie_key = 'Generic'` followed by a single-key lookup (`YoutubeDL.py:1698-1702`, VERIFIED) — which
  shows a catch-all can be exposed as an addressable adapter without being the default terminator.
- Keep the GoF liability in view: any design where dispatch *can* fall through has, per the pattern's
  own Consequences, no guarantee of receipt. A registry lookup cannot fall through — its total
  function is `key ∈ keys ? adapter : throw`. **That is the structural reason the registry is
  fail-closed for free and the chain is not.**

## 3.4 SECURITY: `import(\`../adapters/${platform}.js\`)` guarded by `existsSync`

### Vulnerability class

- **CWE-829: Inclusion of Functionality from Untrusted Control Sphere** — the correct primary class.
  **VERIFIED** <https://cwe.mitre.org/data/definitions/829.html>: *"The product imports, requires, or
  includes executable functionality (such as a library) from a source that is outside of the intended
  control sphere."* Applicable Platforms: *"Languages: Class: Not Language-Specific."* Child of
  CWE-669; **parent of CWE-98**.
- **CWE-22: Improper Limitation of a Pathname to a Restricted Directory ('Path Traversal')** — the
  mechanism. **VERIFIED** <https://cwe.mitre.org/data/definitions/22.html>: *"The product uses external
  input to construct a pathname that is intended to identify a file or directory that is located
  underneath a restricted parent directory, but the product does not properly neutralize special
  elements within the pathname that can cause the pathname to resolve to a location that is outside of
  the restricted directory."*
- **Do NOT cite CWE-98 unqualified.** **VERIFIED** <https://cwe.mitre.org/data/definitions/98.html>:
  its full name is *"Improper Control of Filename for Include/Require Statement in PHP Program ('PHP
  Remote File Inclusion')"*, its description begins *"The PHP application receives input…"*, and its
  Applicable Platforms lists *"PHP (Often Prevalent)"*. It is the **PHP-scoped child** of CWE-829.
  Cite CWE-829 + CWE-22, noting CWE-98 as the PHP sibling.

### Recognized guidance that the fix is an ALLOWLIST/enumerated map, not an existence check

**CWE-22, Potential Mitigations — Phase: Architecture and Design, Strategy: Enforcement by
Conversion** (VERIFIED, same URL) — this is the sentence that names our fix exactly:

> "When the set of acceptable objects, such as filenames or URLs, is limited or known, create a
> mapping from a set of fixed input values (such as numeric IDs) to the actual filenames or URLs, and
> reject all other inputs."

The identical mitigation text appears on **CWE-829** (VERIFIED). And CWE-22's Input Validation
strategy (VERIFIED):

> "Assume all input is malicious. Use an 'accept known good' input validation strategy, i.e., use a
> list of acceptable inputs that strictly conform to specifications."

**OWASP Input Validation Cheat Sheet** (VERIFIED,
<https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html>, "Allowlist vs
Denylist"):

> "Allowlist validation is appropriate for all input fields provided by the user. Allowlist validation
> involves defining exactly what IS authorized, and by definition, everything else is not authorized."

> "It is a common mistake to use denylist validation in order to try to detect possibly dangerous
> characters and patterns … but this is a massively flawed approach as it is trivial for an attacker
> to bypass such filters."

and, on file handling: *"The client should not be able to specify the file path; it should be defined
by the server."*

**Node.js official security best-practices — VERIFIED NEGATIVE, report this honestly.**
<https://nodejs.org/en/learn/getting-started/security-best-practices> has these sections: Intent,
Document Content, Threat List, DoS of HTTP server (CWE-400), DNS Rebinding (CWE-346), Exposure of
Sensitive Information (CWE-552), HTTP Request Smuggling (CWE-444), Timing Attacks (CWE-208), Malicious
Third-Party Modules (CWE-1357), Memory Access Violation (CWE-284), Monkey Patching (CWE-349),
Prototype Pollution (CWE-1321), Uncontrolled Search Path Element (CWE-427), Node.js Permission Model,
Experimental Features in Production, OpenSSF Tools. **It does not cover path traversal, untrusted input
in file paths, or dynamic `import()` of user-controlled specifiers.** Do not cite it for the allowlist
fix. It is relevant only for its threat-model framing (CWE-427, verbatim): *"The Node.js threat model
considers the file system in the environment accessible to Node.js as trusted… Node.js loads modules
following the Module Resolution Algorithm. Therefore, it assumes the directory in which a module is
requested (require) is trusted."* — i.e. Node explicitly declines to defend this; it is the
application's job.

Node's ESM docs **do** state the resolution-mismatch hazard directly, which is the load-bearing
citation here (VERIFIED, <https://nodejs.org/api/esm.html>, "URLs"):

> "ES modules are resolved and cached as URLs. This means that special characters must be
> percent-encoded, such as `#` with `%23` and `?` with `%3F`."

> "Given the differences between URL and path resolution (such as percent encoding details), it is
> recommended to use `url.pathToFileURL` when importing a path."

and in ESM_RESOLVE:

> "If *resolved* contains any percent encodings of *"/"* or *"\\"* (*"%2F"* and *"%5C"* respectively),
> then 1. Throw an *Invalid Module Specifier* error."

### Can it actually escape on Node 24? — EMPIRICALLY VERIFIED, YES

Probe reproducing the incumbent shape exactly (`src/probe.js` importing `../adapters/${platform}.js`,
guarded by `existsSync(path.join(adaptersDir, platform + '.js'))`), **Node v24.18.0, win32**:

| `platform` payload | `existsSync` guard | what `import()` loaded |
|---|---|---|
| `youtube` | `true` | intended `adapters/youtube.js` |
| **`../secret/pwned`** | `true` | **`secret/pwned.js` — ESCAPED the adapters dir** |
| **`..\secret\pwned`** (backslash) | `true` | **`secret/pwned.js` — ESCAPED** |
| **`%2e%2e/secret/pwned`** | `false` | **`secret/pwned.js` — ESCAPED** |
| `..%2fsecret%2fpwned` | `false` | throws `ERR_INVALID_MODULE_SPECIFIER` |
| `../../../../../../../../Windows/System32/x` | `false` | `ERR_MODULE_NOT_FOUND` |
| `C:/Windows/System32/x` | `false` | `ERR_MODULE_NOT_FOUND` |
| `/etc/passwd` | `false` | `ERR_MODULE_NOT_FOUND` |
| `file:///C:/Windows/x` | `false` | `ERR_MODULE_NOT_FOUND` |
| `node:fs` | `false` | `ERR_MODULE_NOT_FOUND` |
| `youtube.js?x=1#` | `false` | intended `youtube.js` (query/fragment stripped) |
| `YOUTUBE` | `true` | intended `youtube.js` (Windows case-insensitive FS) |
| `you%74ube` | `false` | intended `youtube.js` (URL decoding) |

`import.meta.resolve('../adapters/../secret/pwned.js')` returns
`file:///…/esmprobe/secret/pwned.js` — resolution outside the directory, confirmed directly.
**All VERIFIED (probe).**

**What this establishes and what it refutes:**

1. **Relative traversal escapes. VERIFIED.** `../secret/pwned` loads and executes a module outside
   `adapters/`, and the `existsSync` guard **returns `true`** for it — the guard provides zero
   protection against the payload that matters, because the file genuinely exists.
2. **Absolute-path and scheme payloads do NOT escape. VERIFIED — and this REFUTES an over-broad
   claim.** Because `platform` is interpolated in the *middle* of the specifier, the result can never
   begin with `/`, a drive letter, `file:`, or `node:`. Traversal is the attack; absolute-path
   injection and builtin-module injection are not available in this template. Say so precisely rather
   than overstating.
3. **Windows backslashes traverse. VERIFIED on win32; NOT tested on POSIX — mark platform-specific.**
4. **The guard and the loader use different resolvers, and they disagree. VERIFIED.** `existsSync`
   takes a **filesystem path**; `import()` takes a **URL specifier**. Two resolution algorithms.
   Rows 3, 11, 12, and 13 above are all cases where one says one thing and the other says another.
   This argument holds *independently of any payload*: a guard written in the path domain cannot
   soundly constrain a load performed in the URL domain — which is precisely why Node's own docs
   recommend `pathToFileURL` "given the differences between URL and path resolution."

5. **The standard hardening is ALSO bypassed. VERIFIED (probe) — this is the sharpest result.**
   The usual fix people reach for is a containment check:
   `path.resolve(adaptersDir, platform + '.js').startsWith(adaptersDir + path.sep)`.

   | `platform` | containment check says | where `import()` actually resolved | loaded |
   |---|---|---|---|
   | `youtube` | contained ✓ | inside | intended |
   | `../secret/pwned` | **not contained** ✗ (correctly blocked) | outside | escaped |
   | **`%2e%2e/secret/pwned`** | **contained ✓ (check PASSES)** | **outside** | **ESCAPED** |
   | **`.%2e/secret/pwned`** | **contained ✓ (check PASSES)** | **outside** | **ESCAPED** |
   | `..%2fsecret%2fpwned` | contained ✓ | — | `ERR_INVALID_MODULE_SPECIFIER` |

   Percent-encoding the **dots** (`%2e`) defeats the path-based check while the URL resolver decodes
   them and traverses. Encoding the **slash** (`%2f`) is the only variant Node blocks — exactly as
   ESM_RESOLVE documents ("If *resolved* contains any percent encodings of `/` or `\` … Throw an
   *Invalid Module Specifier* error"), which is why `%2e` slips through and `%2f` does not.

   **Conclusion: sanitizing the string is not a fix, and neither is a containment check.** Every
   filter operates in the path domain while the load happens in the URL domain, and the two decode
   differently. The only construction that closes the gap is the one CWE-22 names: **an enumerated map
   from a fixed set of input values to statically-written specifiers**, where the untrusted string is
   used as a *lookup key* and never reaches the resolver at all:

   ```js
   const ADAPTERS = {
     youtube: () => import('./adapters/youtube.js'),
     vimeo:   () => import('./adapters/vimeo.js'),
   };
   const load = ADAPTERS[key];               // use Object.hasOwn / null-prototype map
   if (!load) throw new UnknownAdapterError(key, Object.keys(ADAPTERS));
   ```

   Every specifier is a string literal the bundler and type-checker can see; the untrusted value
   indexes an object instead of building a path. This is the same construction the sibling research
   found restores TypeScript checkability — **the security fix and the type-safety fix are the same
   change**, which is worth stating plainly when the decision is made.

   One residual note: use a `null`-prototype object or a `Map`, and `Object.hasOwn` rather than a
   truthiness check, so keys like `constructor`, `__proto__`, or `toString` cannot resolve to
   inherited members. **UNVERIFIED for this codebase** (not probed); standard practice for
   user-keyed lookup objects.

---

## Appendix — claims I could NOT verify

- **GoF page number, edition, printing, publisher, year.** The reached source (publisher-hosted
  excerpt) states title and authors only. Wording VERIFIED; bibliographic detail **UNVERIFIED**.
- **HTML spec rationale for exactly three grades rather than two or a boolean.** The spec states a
  rationale for *graded confidence*; it states **none** for the number three. Any such rationale would
  be fabrication. **NOT STATED.**
- **mimesniff row-order-is-sequential** is an inference from Infra's `for each` definition, since
  mimesniff's patterns live in an HTML `<table>` rather than a formally-designated Infra list. The
  *first-match-returns* control flow is VERIFIED; the *ordering* reading is **inferred**.
- **Vite: plugins within a bucket run in `plugins`-array order.** Not stated on vite.dev.
  **UNVERIFIED** (documented negative; Rollup states it, Vite does not).
- **Webpack: default behaviour when multiple top-level `module.rules` match.** Not stated on
  webpack.js.org. **UNVERIFIED** (documented negative; implied by "All applied parser options are
  merged").
- **Backslash traversal on POSIX.** Probed on win32 only. **UNVERIFIED** elsewhere.
- **Prototype-chain key collisions** (`__proto__` etc.) in the proposed registry: not probed.
  **UNVERIFIED.**
- **`_ALL_CLASSES`** as a current yt-dlp symbol: **REFUTED** at this pin — the structures are
  `_CLASS_LOOKUP` and the `globals.extractors` Indirect.
