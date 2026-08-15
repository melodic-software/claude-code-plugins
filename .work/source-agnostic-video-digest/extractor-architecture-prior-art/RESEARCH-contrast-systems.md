---
topic: extractor-architecture-prior-art
section: contrast-systems
abstract: Five contrast systems establish that scored dispatch is an upgrade forced by key collision, not handler count — and gallery-dl's BaseExtractor solves the self-hosted-instance problem yt-dlp has left open for four years, by compiling a user-extensible host table into the pattern.
claims:
  - claim: "gallery-dl parameterizes ONE extractor class over many hosts by compiling a data table of instances into the pattern at load time, with a scheme-prefix escape for unknown hosts and user-config-registered instances."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/common.py:1084-1125 (BaseExtractor.update / _init_category), clone @ 86047cf6"
        tier: 0
        pool: "gallery-dl source"
      - url: "empirical: running the code produced pattern (?:mastodon:(https?://[^/?#]+)|(?:https?://)?(mastodon\\.social()|pawoo\\.net()|baraag\\.net()))"
        tier: 0
        pool: "gallery-dl source (executed)"
  - claim: "gallery-dl ships an adapter whose entire implementation is delegation to another whole system (the ytdl extractor), registered like any other and positioned second-to-last in the fallback tail."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/__init__.py:12-267 (modules list tail: directlink, recursive, oauth, noop, ytdl, generic)"
        tier: 0
        pool: "gallery-dl source"
  - claim: "FFmpeg splits the declarative claim surface (public AVInputFormat) from the behavioural vtable (internal FFInputFormat) across a public/private ABI boundary."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "libavformat/avformat.h:565-604 (public struct, metadata only)"
        tier: 0
        pool: "FFmpeg source"
      - url: "libavformat/demux.h:66 (FFInputFormat embeds AVInputFormat p as first member)"
        tier: 0
        pool: "FFmpeg source"
  - claim: "Pygments' framework clamps analyse_text output to [0,1], converts exceptions and falsy returns to 0.0, and forces staticmethod-ness, so a misbehaving lexer can be wrong but cannot be out of contract or crash dispatch."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "pygments/util.py make_analysator; pygments/lexer.py LexerMeta.__new__"
        tier: 0
        pool: "Pygments source"
      - url: "pygments CHANGES: 'Do not fail in analyse_text methods (#618)'"
        tier: 1
        pool: "Pygments maintainers"
  - claim: "Tika treats detection and parsing as two independently-extensible interfaces communicating through a shared Metadata structure, and its hint policy forbids a declared type from overruling content evidence."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "org.apache.tika.parser.Parser / Detector interfaces; MimeTypes.applyHint (Tika 3.3.2)"
        tier: 0
        pool: "Apache Tika source"
      - url: "https://tika.apache.org/3.2.3/parser.html (five stated design criteria)"
        tier: 1
        pool: "Apache Tika docs"
produced_by: phase-3-preferred-sources
---

# Contrast systems

Five systems, chosen to bracket the dispatch question. **Babel and unified/remark were cut** — both
dispatch by an explicit user-supplied plugin list rather than inferring a handler from the input, so
they do not bear on the live question. That cut is recorded in `research-checklist.md`.

| | Claim key | Arbitration | Cheap index | Fallback | Third-party seam |
|---|---|---|---|---|---|
| **yt-dlp** | `_VALID_URL` regex | first match over an ordered dict | generated `lazy_extractors.py` | `GenericIE`, **asserted last** | `yt_dlp_plugins` namespace packages |
| **gallery-dl** | `cls.pattern` regex | first match over `_list_classes()` | 254-entry `modules` list, lazily imported as scanned | ordered tail: `directlink`, `recursive`, `oauth`, `noop`, `ytdl`, `generic` | `--extractor-source` module paths, **which sort ahead of built-ins** |
| **streamlink** | `@pluginmatcher(pattern, priority)` | **highest priority wins**; ties by iteration order | checksum-validated `_plugins.json` | **none** — `match_url` returns `None` | sideload dirs override built-ins **by module name** |
| **FFmpeg** | `read_probe` on a byte buffer | **numeric score 0-100, highest wins; tie ⇒ refuse** | n/a (all demuxers compiled in) | none — `AVERROR_INVALIDDATA` | build-time only |
| **Pygments** | filename glob + mimetype + `analyse_text` | 4-key lexicographic sort, framework-clamped score | generated `lexers/_mapping.py` | `TextLexer` at `priority = 0.01` | entry points, appended after built-ins |
| **Tika** | `getSupportedTypes()` MIME set | **lattice specialization**, not score | `tika-mimetypes.xml` (8,993 lines of data) | `EmptyParser` — zero types, valid empty result | `ServiceLoader` + `tika-config.xml` exclude/pin |

## gallery-dl — the host-registry shape yt-dlp lacks

This is the single most directly applicable contrast finding, because it solves the case yt-dlp's
PR #1791 has left open since 2021: **many hosts running the same software.**

`BaseExtractor.update()` (`common.py:1084-1125`):

```python
@classmethod
def update(cls, instances):
    if extra_instances := config.get(("extractor",), cls.basecategory):   # user-added rows
        for category, info in extra_instances.items():
            if isinstance(info, dict) and "root" in info:
                instances[category] = info

    pattern_list = []
    instance_list = cls.instances = []
    for category, info in instances.items():
        instance_list.append((category, root, info))
        pattern = info.get("pattern") or re.escape(root[root.index(":") + 3:])
        pattern_list.append(pattern + "()")        # empty capture group = index marker

    return (f"(?:{cls.basecategory}:(https?://[^/?#]+)|"
            f"(?:https?://)?(?:{'|'.join(pattern_list)}))")
```

**The host list is compiled into the pattern**, and each instance contributes an **empty capture group**
used purely as an index marker; `_init_category` finds the first non-`None` group and binds `category`,
`root`, and `self.config_instance = info.get` — per-host data without a per-host class. Verified by
executing the code:

```
MASTODON BASE: (?:mastodon:(https?://[^/?#]+)|(?:https?://)?(?:mastodon\.social()|pawoo\.net()|baraag\.net()))(?:/web)?
```

Three escape hatches, all in that one method:

1. **A scheme prefix for unknown hosts** — `mastodon:https://example.social/@foo` resolves with **no
   config at all**, taking its category from the domain.
2. **Config-registered instances.** `LolisafeExtractor` ships `update({})` — an **empty** table. After
   `config.set(("extractor","lolisafe"), "xbunkr", {"root": "https://xbunkr.com"})` the pattern rebuilds
   and the URL resolves. **An adapter can ship dormant, with zero hosts, activated entirely by user
   config.** The contract test knows about this case: `if cls.basecategory and not cls.instances: continue`.
3. **Per-instance regex override** — `info.get("pattern")` beats `re.escape(root)` for subdomain wildcards.

**Failure mode prevented:** 40 near-identical classes for 40 instances of the same software, and no way
for a user to point the tool at a private instance without patching source.

### The delegate-to-another-system adapter

gallery-dl's `modules` list tail, in order: `directlink`, `recursive`, `oauth`, `noop`, **`ytdl`**,
`generic`. **`ytdl` is an adapter whose entire implementation is "hand this to yt-dlp"** — registered
like any other adapter, positioned second-to-last. Its result-shape seam is the reserved-key set
`_ytdl_instance`, `_ytdl_info_dict`, `_ytdl_manifest`, `_ytdl_params`, `_ytdl_extra`.

Directly applicable: our pipeline already shells out to yt-dlp, so **yt-dlp is an adapter, not the
substrate**. That changes what the method set must contain — the contract must not assume adapters do
their own HTTP.

### The fallback tail, and what "unsupported" costs

- `directlink` — matches any URL whose path ends in a known media extension, with a **dynamic**
  subcategory derived from the domain.
- `recursive` — scheme-prefixed only (`r:` / `recursive:`); scrapes every URL out of a page and yields
  each as `Message.Queue`.
- `generic` — **opt-in catch-all whose regex is mutated at import time by config** (`generic.py:22-35`):
  `pattern = r"(?i)(?P<generic>g(?:eneric)?:)"` and, only `if config.get(…, "enabled")`, `pattern += r"?"`
  making the prefix optional.
- **Unresolvable is not fatal.** `find()` returns `None`; `job.py:611-612` writes the URL to an
  unsupported-URLs file and the run continues.

### Streaming messages, both sides of the trade

`items()` yields uniform 3-tuples `(message_id, str, dict)`; consumers destructure unconditionally then
branch (`job.py:222`). Live types: `Directory` (2), `Url` (3), `Queue` (6). Retired and commented out:
`Version` (1), `Headers` (4), `Cookies` (5), `Urllist` (7), `Metadata` (8) — **numbers never reused**.

**0/1/N per post:** `Directory` opens a scope, then zero-to-N `Url` messages. **N = 0 is legal and
common** — a post whose media was all filtered yields a `Directory` and nothing after it, and
`job.py:246-250` tracks a `process` flag so subsequent messages are skipped.

**`Message.Queue` = delegation**, in two flavors: **bound** (`kwdict["_extractor"] = SomeClass`, so
`job.py:541-542` skips the registry entirely) and **unbound** (no `_extractor`; `job.py:544` calls
`extractor.find(url)` and applies a user-configurable extractor filter). The consumer spawns a **child
job of the same class**, so recursion is homogeneous; a shared `visited` set prevents cycles.

**What streaming buys:** memory (`AsynchronousMixin` runs `items()` on a daemon thread feeding a
`queue.Queue(5)` — real backpressure), incremental output, early failure (a mid-stream exception leaves
everything already yielded downloaded), and **interception** — `job.dispatch` inserts predicates and
hooks *between* producer and consumer, which a returned object gives no place to stand.

**What it costs, with gallery-dl's own code as proof.** `GalleryExtractor.items()`:

```python
try:
    data["count"] = len(imgs)
except TypeError:
    pass                      # generator: 'count' silently absent
```

`{count}` exists in the format namespace only if that adapter's `images()` returned a materialized list.
Two adapters, same base class, different downstream formatting — for a reason invisible at the seam.
`page-reverse` is silently unavailable in the generator branch. And **validation requires execution**:
the test harness must run the whole extraction over the live network to learn a count.

## Streamlink — declarative claims, explicit priority, and one honest warning

- **Priority is NOT the override mechanism.** Override is *module-name shadowing*: `iter_matchers()`
  yields sideloaded plugins first and **skips lazy built-in entries whose name is already loaded**.
  A sideloaded plugin under a *different* name gets no advantage at all. Only **2 of 135** plugins use
  a non-default priority, both `LOW_PRIORITY` generic patterns (`hls.py`, `dash.py`). **Priority exists
  so a generic pattern loses to a site-specific one** — nothing else.
- **`NO_PRIORITY` is a declared-but-never-dispatched level:** `priority` initializes to `0` and the test
  is strict `>`, so a `0`-priority matcher can never win, while the URL shape stays visible in
  `Plugin.matches` and `--show-matchers`. *(Mechanism verified in source; **no built-in uses it**, so
  the intent is **inferred**.)*
- **Named matchers model URL shapes; separate plugins model sources.** 135 plugins declare matchers;
  **44** declare more than one; **38** use **125** named matcher decorators. Twitch declares four —
  `player`, `clip`, `vod`, `live` — sharing one OAuth/API/ad-filtering machine. In 7.1.0 (#6285) the
  maintainers deliberately **replaced verbose catch-all regexes with multiple simple named matchers** —
  they treat "one regex covering N shapes" as the anti-pattern, not "N matchers on one plugin".
- **The technique worth stealing outright: canonicalize in the constructor.** `plugins/youtube.py:84-97`
  declares four named matchers and then **rewrites `self.url` to one canonical shape** in `__init__`.
  Assigning `self.url` re-runs the whole matcher set through the property setter, so `matches`/`match`
  stay consistent. Everything downstream sees one shape. Source comment: *"translate input URLs to be
  able to find embedded data and to avoid unnecessary HTTP redirects."*
- **The declarative tax is real and was measured.** The `_plugins.json` payoff was modest and the
  maintainer said so in #5822: 1.32s→1.30s, 53MB→50MB — *"It's not that much faster than I was hoping
  for, but it's an improvement nonetheless."* The priority constants are **duplicated as literals** in
  `build_backend/plugins_json.py:39-42` so the build-time parser can resolve them without importing
  streamlink.

## FFmpeg — numeric confidence, and the calibration tax

Scale (`libavformat/avformat.h:478-485`): `AVPROBE_SCORE_RETRY` 25, `AVPROBE_SCORE_EXTENSION` 50,
`AVPROBE_SCORE_MIME_BONUS` 30, `AVPROBE_SCORE_MAX` 100.

Four things from `format.c:191-230` worth extracting precisely:

1. **The extension hint is asymmetric.** A demuxer *with* `read_probe` gets extension match only as a
   **floor of 1**; one *without* gets the full **50**. That asymmetry is what makes declarative-only and
   content-probing handlers commensurable on one scale.
2. **The MIME bonus is additive and unconditional** — a demuxer with zero content evidence but a matching
   `mime_type` reaches 30, above the 25 retry threshold, so a bare MIME match is accepted with **no
   "misdetection possible" warning and no re-probe**. The MIME string comes from the HTTP `Content-Type`.
   *(Exploitability **inferred** from the arithmetic; no filed CVE found.)*
3. **A tie means refusal, not an arbitrary pick** — `else if (score == score_max) fmt = NULL;`
4. **Stricter early, permissive late** — the probe loop accepts at 25 while more data is available and at
   0 on the last pass, logging *"Format %s detected only with low score of %d, misdetection possible!"*

**The calibration tax, visible in shipping source:** `wavdec.c` returns `AVPROBE_SCORE_MAX - 1` with the
comment *"the returned score is decreased to avoid a probe conflict between ACT and WAV"*; `mp3dec.c`
carries *"keep this in sync with ac3 probe"*. **These are calibration constants encoding cross-handler
knowledge inside independently-authored handlers** — `wav_probe` cannot be reviewed correctly without
knowing ACT exists. The header itself warns: *"You should usually not use extension format guessing
because it is not reliable enough."*

## Pygments — the framework clamps the score

`LexerMeta.__new__` wraps every subclass's `analyse_text` through `make_analysator`, which **clamps to
[0,1], converts exceptions to 0.0, converts falsy to 0.0, and forces staticmethod-ness.** FFmpeg does
none of this. **A misbehaving Pygments lexer can be wrong but cannot be out of contract, and cannot
crash dispatch.** Origin recorded in CHANGES: *"Do not fail in analyse_text methods (#618)."*

**Documented score inflation, and the fix that became a convention:** CHANGES —
*"Reduce `TeraTerm` lexer score -- it used to match nearly all languages (#1256)"*. One handler's
overconfident `analyse_text` silently degraded guessing for **every** language. The fix was to drop to
the **epsilon convention**, `return 0.01` — "enough to break my one known collision, nothing more."

**`alias_filenames`** is the explicit "I am a *candidate* for this pattern, not an owner" declaration —
every HTML template lexer lists `*.html` there rather than in `filenames`, buying candidacy in guessing
without claiming ownership in filename dispatch. A useful shape.

## Apache Tika — detection and parsing as two interfaces

Two independently-extensible interfaces, communicating through a shared `Metadata` structure rather than
a direct call — which is why caller-injected `CONTENT_TYPE_USER_OVERRIDE` can short-circuit detection
with no dispatcher special-casing.

**The hint policy is the exact inverse of FFmpeg's** (`MimeTypes.applyHint`):

```java
for (final MimeType type : possibleTypes) {
    if (hint.equals(type) || registry.isSpecializationOf(hint.getType(), type.getType()))
        return Collections.singletonList(hint);
}
return possibleTypes;   // Hint didn't help, sorry
```

A hint may *select among* magic candidates or *specialize* one; it may **never overrule** magic, and
becomes the answer only when magic found nothing. It also explicitly ignores an *interpreted* type
derived from an `http(s)` URL's filename. **For anything fetched over HTTP, Tika's posture is the
defensible one.**

Other transferable pieces:

- **The type lattice is data, not code** — `tika-mimetypes.xml`, 8,993 lines, with the calibration
  comments living **in an editable data file** rather than inside a compiled handler.
- **`sub-class-of` makes the supertype walk load-bearing:** an unregistered `text/iso19139+xml` falls
  back to the `application/xml` parser, then `text/plain`. **A new subtype gets a working-if-imperfect
  handler for free.**
- **Type claims are rewritable from outside the handler** — `ParserDecorator.withTypes(parser, types)` /
  `withoutTypes(...)` let an operator retarget an existing handler without touching its code.
- **Third-party precedence is a documented ordering rule, not a score** — `DefaultParser` sorts by name
  then **reverses**, with the comment *"put the Tika parsers first so that non-Tika (user supplied)
  parsers can take precedence."*
- **A broken third-party handler is skipped, not fatal** — `LoadErrorHandler` defaults to `IGNORE`, with
  `WARN`/`THROW` as dials.
- **The composite enforces the contract and names the offender** —
  `throw new TikaException("TIKA-198: Illegal IOException from " + parser, e)`.
- **The five stated design criteria are the best ready-made acceptance rubric in the corpus**
  (`parser.html`, verbatim): streamed parsing, structured content, **input metadata**, output metadata,
  **context sensitivity**. The last two are the ones most commonly omitted.
- ⚠️ **Version drift:** Tika 4.0.0-beta changed both interfaces — `parse(TikaInputStream, …)` and
  `detect(TikaInputStream, Metadata, ParseContext)`. The direction is instructive: **narrow the input
  type to the replayable handle, and thread the context through detection too.** In Tika 3, container
  detection degrades *silently* to cheap MIME magic when handed a plain `InputStream`; Tika 4 removes
  that by putting the capability in the signature. **Capability requirements belong in the interface
  signature, not in prose.**
