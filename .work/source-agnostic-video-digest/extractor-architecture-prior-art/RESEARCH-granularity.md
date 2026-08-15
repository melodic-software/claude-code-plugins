---
topic: extractor-architecture-prior-art
section: granularity
abstract: All three mature systems converge on ONE coarse extract method plus an inverted-control intermediate base; per-source quirks are expressed as class attributes, namespaced config, and at most one predicate inside a shared loop — never duplicated machinery.
claims:
  - claim: "yt-dlp's acquisition seam is one required method plus four optional lifecycle stubs; the template method extract() owns initialization, geo-bypass retry, and error tagging."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/extractor/common.py:757-789 (extract), :654-672 (initialize), :818-832 (the four stubs)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "Streamlink has exactly one abstract method across 135 plugins; its optional overrides are classmethods computing a value, not lifecycle callbacks. There is no pre_extract, post_process, or on_error."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "src/streamlink/plugin/plugin.py:381 (abstractmethod), :104-141 (stream_weight)"
        tier: 0
        pool: "streamlink source"
      - url: "src/streamlink/plugins/twitch.py:876 (stream_weight override), plugins/youtube.py:101"
        tier: 0
        pool: "streamlink source"
  - claim: "gallery-dl offers both a coarse seam and an inverted-control intermediate: GalleryExtractor implements items() itself and asks subclasses for metadata()/images()/assets()/login(), reducing a typical leaf adapter to six lines."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/common.py:871-953 (GalleryExtractor), :956-966 (ChapterExtractor), :969-1007 (MangaExtractor)"
        tier: 0
        pool: "gallery-dl source"
      - url: "gallery_dl/extractor/twitter.py:797-806 (six-line leaf)"
        tier: 0
        pool: "gallery-dl source"
  - claim: "A per-site quirk needing a decision inside a shared retry loop is expressed as ONE overridable predicate; gallery-dl's _handle_429 is the only such override across 257 modules."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/common.py:310 (_handle_429 = util.false), :227-230 (call site in retry loop)"
        tier: 0
        pool: "gallery-dl source"
      - url: "gallery_dl/extractor/skeb.py:36-45 (the sole override)"
        tier: 0
        pool: "gallery-dl source"
  - claim: "yt-dlp's per-extractor config (--extractor-args / _configuration_arg) is namespaced but stringly-typed, unvalidated, and undiscoverable; a typo is silently ignored, and it was introduced by a direct-to-master commit with no PR or design discussion."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "yt_dlp/extractor/common.py:4023-4034 (local checkout)"
        tier: 0
        pool: "yt-dlp source"
      - url: "commit 5d3a0e794b50a7f2524bdf37a886e0f436eb2f14; gh api .../commits/<sha>/pulls returns empty"
        tier: 0
        pool: "GitHub API"
  - claim: "Streamlink's @pluginargument derives the CLI flag from the module name and carries type, validation kwargs, requires, and sensitive — the declarative counterpart to yt-dlp's string bag."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "src/streamlink/plugins/twitch.py:745-826 (ten declared arguments)"
        tier: 0
        pool: "streamlink source"
      - url: "src/streamlink/plugin/plugin.py:36-47 (_PLUGINARGUMENT_TYPE_REGISTRY)"
        tier: 0
        pool: "streamlink source"
produced_by: phase-2-targeted-and-falsification
---

# Granularity of the acquisition seam

## Recommendation

**ONE coarse extract method, plus an inverted-control intermediate base for the common shape. No
lifecycle hook zoo. Add a fine hook only when a *shared loop* needs one decision.**

## The three systems converge from different directions — documented, Tier 0

### yt-dlp: 1 required + 4 optional stubs, wrapped in two template methods

The hook surface is tiny; the helper surface is enormous. The complete set of overridable lifecycle
points (`common.py:818-832`):

```python
def _initialize_pre_login(self):   """ Initialization before login. Redefine in subclasses."""
def _perform_login(self, u, p):    """ Login with username and password. Redefine in subclasses."""
def _real_initialize(self):        """Real initialization process. Redefine in subclasses."""
def _real_extract(self, url):      raise NotImplementedError(...)
```

Plus `suitable()` (dispatch) and the two embed hooks (`_extract_embed_urls`, `_extract_from_webpage`).

**`extract()` (`common.py:757-789`) is the template method and it owns real work:**

- calls `initialize()`
- the **geo-bypass retry loop** — `for _ in range(2)`, catching `GeoRestrictedError` and retrying once
  with a fabricated `X-Forwarded-For` (`__maybe_fake_ip_and_retry`, `:791-804`)
- stamps `__x_forwarded_for_ip` onto the result
- applies the `no-live-chat` compat option to subtitles
- **error tagging** — every escaping `ExtractorError` gets `video_id`, `ie`, and `traceback` attached;
  `IncompleteRead` becomes a friendly *"A network error has occurred"*; bare `KeyError`/`StopIteration`
  become *"An extractor error has occurred"* with the video id attached

**`initialize()` (`common.py:654-672`) owns the login ordering**, including a notable guard: it calls
`_perform_login` only when `type(self)._perform_login is not InfoExtractor._perform_login` — i.e. only
if the subclass actually overrode it — and otherwise warns that password login is unsupported for the
site. The ordering `_initialize_pre_login` → `_perform_login` → `_real_initialize` is fixed by the
base, and `self._ready` makes it idempotent.

### Streamlink: one abstract method, and the optional overrides compute values

`_get_streams()` is the sole `@abc.abstractmethod` across 135 plugins. The optional overrides are
*classmethods returning a value*, not callbacks: `stream_weight()` (twitch maps `"source"` →
`sys.maxsize`; youtube handles `_3d` and HFR names), `default_stream_types()`, and the four metadata
accessors. **There is no `pre_extract`, no `post_process`, no `on_error`.** Exactly **one** plugin of
135 touches session options at all (`plugins/showroom.py:28`).

### gallery-dl: both seams, with inversion of control at the intermediate layer

`GalleryExtractor` (`common.py:871-953`) implements `items()` itself and declares four subclass hooks:

```python
def items(self):
    self.login()
    page = self.request(self.page_url, notfound=self.subcategory).text if self.page_url else None
    data = self.metadata(page)
    imgs = self.images(page)
    assets = self.assets(page)
    ...
    yield Message.Directory, "", data
    for data[enum_key], (url, imgdata) in images:
        ...
        text.nameext_from_url(url, data)
        yield Message.Url, url, data
```

The **framework**, not the adapter, owns: page fetch, the `login()` call, count derivation, 1-based
numbering, `page-reverse` ordering, filename/extension parsing, and emission order. Subclasses return
two plain values. `ChapterExtractor` is a **12-line subclass** overriding four format strings and
`enum = "page"`. `MangaExtractor` is the same shape but yields `Message.Queue` and stamps
`data["_extractor"] = self.chapterclass`.

The coarse seam stays available for adapters that need it — twitter, instagram, deviantart all
implement `items()` directly. A typical leaf is six lines (`gallery_dl/extractor/twitter.py:797-806`):

```python
class TwitterHomeExtractor(TwitterExtractor):
    """Extractor for Twitter home timelines"""
    subcategory = "home"
    pattern = BASE_PATTERN + r"/home(?:/fo(?:llowing|r[-_ ]?you()))?/?$"
    example = "https://x.com/home"

    def tweets(self):
        return self.api.home_timeline() if self.groups[0] is None else ...
```

## Per-site quirks without duplicating machinery — three tiers, zero duplication

### Tier (a) — attribute only

`gallery_dl/extractor/instagram.py:28-31`:

```python
cookies_domain = ".instagram.com"
request_interval = (6.0, 12.0)     # randomized 6-12s between requests
```

`request_interval` is read once in `_init_options` (`common.py:485-487`) as the **default** for the
user-facing `sleep-request` config key, and enforced by the base `request()` loop (`common.py:175-179`).
Instagram writes two lines; the sleeping, the jitter, and the user override all come free. When
linear/exponential 429 backoff landed in gallery-dl 1.32.0, **all 920 adapters got it.**

### Tier (b) — ONE predicate inside the shared loop

Base declares a stub (`common.py:310`): `_handle_429 = util.false`, called from inside the retry loop
(`common.py:227-230`):

```python
if code == 429 and self._handle_429(response):
    continue                       # retry immediately, no backoff
elif code == 429 and self._interval_429:
    pass
elif code not in retry_codes and code < 500:
    break
```

`skeb.py:36-45` overrides **only that predicate** — its 429 is really a cookie challenge. It is the
**only** override of `_handle_429` in 257 modules. Retry counting, `sleep-429` backoff, `sleep-retries`,
`retry-codes`, timeout, proxies, TLS ciphers, and response dumping all stay in the base.

**This is the pattern to copy when a fine hook is genuinely warranted:** a shared loop that needs one
site-specific decision gets one predicate, not a subclassable loop.

### Tier (c) — auth as a convention over base-provided credential resolution

There is no `login()` on gallery-dl's base. The convention is a pair: a public `login()` that checks
cheap state first, and `_login_impl()` doing the exchange, wrapped in a persistent cache
(`twitter.py:782-795`):

```python
def login(self):
    if self.cookies_check(self.cookies_names):     # already authenticated? cheap exit
        return
    username, password = self._get_auth_info()     # base: config -> netrc -> prompt
    if username:
        return self.cookies_update(self.cache(
            self._login_impl, username, password, _mem=False))
```

`_get_auth_info` (`common.py:448-467`) implements the whole credential chain **once for all 920
adapters**. `self.cache(..., _mem=False)` persists to SQLite so the session cookie survives across
process runs.

yt-dlp's equivalent: `_NETRC_MACHINE` + `_perform_login(username, password)` + the base's
`_get_login_info` / `_get_netrc_login_info` / `_get_tfa_info`, with `supports_login()` derived as
`bool(cls._NETRC_MACHINE)` (`common.py:650-652`). Streamlink's: `@pluginargument` with
`sensitive=True` plus `self.cache` namespaced by module and `save_cookies`/`load_cookies`
(`plugin.py:551-637`, used by 7 plugins).

> ⚠️ API-drift correction: the dispatch's mention of "the `@cache` decorator on login" in gallery-dl is
> historical. `grep -rn "@cache\|@memcache" gallery_dl/extractor/*.py` returns **zero hits** — replaced
> by the explicit `self.cache(...)` method (95 call sites) so the adapter can pass `_key`/`_exp`/`_mem`
> per call site.

## Per-adapter config: namespace it, but DECLARE it

### yt-dlp's `--extractor-args` — right instinct, wrong execution

It exists because site-specific knobs were metastasizing into the global option namespace, one flag per
site. README:2480-2481 shows the removed casualties:

```
--youtube-skip-dash-manifest     Removed alias for --extractor-args "youtube:skip=dash"
--youtube-skip-hls-manifest      Removed alias for --extractor-args "youtube:skip=hls"
```

The implementation (`common.py:4023-4034`):

```python
def _configuration_arg(self, key, default=NO_DEFAULT, *, ie_key=None, casesense=False):
    ie_key = ie_key if isinstance(ie_key, str) else (ie_key or self).ie_key()
    val = traverse_obj(self._downloader.params, ('extractor_args', ie_key.lower(), key))
    if val is None:
        return [] if default is NO_DEFAULT else default
    return list(val) if casesense else [x.lower() for x in val]
```

**Always a list of lowercased strings.** Every call site hand-parses. There is **no key registry and no
validation anywhere** — a typo is silently ignored and the user gets the default with no warning. There
is no way to enumerate what an extractor accepts except reading its source. It cannot be fixed now
precisely because silent-ignore has always been the behaviour, so users depend on it.

Introduced by commit `5d3a0e794b50a7f2524bdf37a886e0f436eb2f14` (pukkandan, 2021-06-25) —
**direct to master, one-line message, no PR.** `gh api repos/yt-dlp/yt-dlp/commits/<sha>/pulls` returns
empty. There is no design discussion to find, which is itself the finding. Searches for
`"extractor-args confusing"` and `"extractor args first class option"` returned **nothing** — no
maintainer has publicly called it a mistake, and the pattern is actively *expanding* (PR #12840 added
`pot_trace`, `fetch_pot`, `bind_to_visitor_id`).

### Streamlink's `@pluginargument` — the declarative counterpart

```python
@pluginargument("supported-codecs", type="comma_list_filter",
                type_kwargs={"acceptable": ["h264", "h265", "av1"], "unique": True}, ...)
```

The CLI flag `--twitch-supported-codecs` is **derived from the module name**, so adding a per-source
knob requires no CLI edit anywhere. `Argument` also supports `requires=` (declaring `username` requires
`password`), `prompt=`, and `sensitive=True`. Validation, `--help` text, and config-file support all
fall out of the declaration. Twitch declares ten.

The tax, stated honestly: because the type had to survive JSON round-tripping into `_plugins.json`,
arbitrary callables were banned for built-ins in favour of a name registry
(`_PLUGINARGUMENT_TYPE_REGISTRY`, `plugin.py:36-47`), with `type_args`/`type_kwargs` restricted to
literals. Declarative-and-serializable is contagious.

## Construction must do no work

Three independent confirmations, all with post-mortems attached:

1. **gallery-dl `8fdab9fb`** (2023-07-25, 68 files) moved every config read and session/cookie setup out
   of `__init__` into a caller-triggered `initialize()`. Maintainer, verbatim: *"This allows, for
   example, to adjust config access inside a Job before most of it already happened when calling
   `extractor.find()`."* Dispatch instantiates candidates just to test the match
   (`__init__.py:270-275`). `initialize()` self-erases (`self.initialize = util.noop`) for idempotency.
2. **gallery-dl made the invariant executable** after breaking it himself — issue #6387, an 8chan
   `_init()` network call breaking AUR package builds on restricted networks: *"This is on me… I'll also
   add another test to make sure this won't happen again."* → `b4c59993`.
3. **Streamlink removed `Plugin.bind()`** in 5.0.0 (#4744): a classmethod storing the session as a
   *class* attribute leaked every `Session` forever. Empirical proof in PR #4768 — `gc.collect()`
   returned **0** before and **3,835** after. Follow-on #5033 moved `Plugin.options` from class to
   instance and deleted `Streamlink.{get,set}_plugin_option()` — *"it adds unnecessary complexity for
   absolutely no gain."*

**Per-request state on the class is a contract that silently forbids concurrency.** You find it only
when you embed the library rather than run the CLI.
