---
topic: extractor-architecture-prior-art
section: required-vs-provided
abstract: The required surface across three mature systems is exactly what the registry cannot infer — a claim, a proof-of-routing example, and one extract method; everything else is a defaulted class attribute.
claims:
  - claim: "yt-dlp's InfoExtractor requires exactly two things of a subclass: _VALID_URL and _real_extract. _real_extract is the only NotImplementedError in the entire 4,176-line base class."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/extractor/common.py:830-832 and :580-594 (local checkout @ 5d6b8c8)"
        tier: 0
        pool: "yt-dlp source"
      - url: "yt_dlp/extractor/common.py:532-534 (contract docstring)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "gallery-dl makes `pattern` required by construction — the registry filters on hasattr(cls, 'pattern') — and `example` required in practice via a CI test that round-trips it through the full registry."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gallery_dl/extractor/__init__.py:336-342 (clone @ 86047cf6)"
        tier: 0
        pool: "gallery-dl source"
      - url: "test/test_extractor.py test_init (clone @ 86047cf6); 920 pattern= / 920 example= / 920 registered classes"
        tier: 0
        pool: "gallery-dl source"
  - claim: "Streamlink has a third required contribution beyond method and matcher — the module-level __plugin__ export — whose absence fails silently."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "src/streamlink/session/plugins.py:201-204 (clone @ c3c2e98)"
        tier: 0
        pool: "streamlink source"
      - url: "src/streamlink/plugin/plugin.py:342-351, :381"
        tier: 0
        pool: "streamlink source"
  - claim: "yt-dlp derives an adapter's arity (_RETURN_TYPE) from its test fixtures rather than from a declaration, and drives user-facing behaviour off that inference."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "yt_dlp/extractor/common.py:3822-3838 (local checkout)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "gallery-dl moved per-extractor test data out of the extractor modules primarily for runtime import cost, not for test/contract decoupling."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/mikf/gallery-dl/issues/4504"
        tier: 1
        pool: "gallery-dl maintainer (mikf)"
      - url: "commits 947a0fc4 / 8d3a16c7 / 518768fa (171 files, +634/-9271)"
        tier: 0
        pool: "gallery-dl source"
produced_by: phase-2-targeted-and-falsification
---

# The required-vs-provided boundary

## Recommendation

**Required = exactly what the registry cannot infer, and nothing else.** Everything a sensible default
can cover becomes a class attribute, so a new adapter's diff is the source's actual differences and
nothing more.

## What each system actually demands — documented, Tier 0

| System | Truly required | Enforcement mechanism | Failure signal |
|---|---|---|---|
| yt-dlp | `_VALID_URL`; `_real_extract` | class attr default `None`; the **only** `NotImplementedError` in the base | `NotImplementedError` at extract time |
| gallery-dl | `pattern`; `example`; `items()` | `_get_classes` filters on `hasattr(cls, "pattern")`; `example` asserted by CI | invisible to registry / `AttributeError` in CI |
| streamlink | `_get_streams()`; ≥1 `@pluginmatcher`; `__plugin__` | `@abc.abstractmethod`; `PluginError` in the `url` setter; **nothing** | `TypeError` / runtime / **silent** |

### yt-dlp, read directly

`common.py:532-534` states the contract in the docstring:

> Subclasses of this should also be added to the list of extractors and should define `_VALID_URL` as
> a regexp or a Sequence of regexps, and re-define the `_real_extract()` and (optionally)
> `_real_initialize()` methods.

`common.py:830-832`:

```python
def _real_extract(self, url):
    """Real extraction process. Redefine in subclasses."""
    raise NotImplementedError('This method must be implemented by subclasses')
```

Every other class attribute ships with a working default (`common.py:580-594`): `_ready=False`,
`_GEO_BYPASS=True`, `_GEO_COUNTRIES=None`, `_GEO_IP_BLOCKS=None`, `_WORKING=True`, `_ENABLED=True`,
`_NETRC_MACHINE=None`, `IE_DESC=None`, `SEARCH_KEY=None`, `_VALID_URL=None`, `_EMBED_REGEX=[]`.
`IE_NAME` and `ie_key()` are **derived** — `cls.__name__[:-2]` (`common.py:834-841`).

The base carries roughly 200 methods. Essentially all are **helpers the base gives free**, not hooks:
`_download_webpage` and its generated `_download_json`/`_download_xml` family, `_search_regex`,
`_search_json`, `_search_json_ld`, `_og_search_*`, `_html_search_meta`, `_search_nextjs_data`,
`_search_nuxt_json`, `_hidden_inputs`, `FormatSort`, `_sort_formats`, `_check_formats`,
`_remove_duplicate_formats`, geo-bypass, `_get_netrc_login_info`, `_get_login_info`, `_get_tfa_info`.
**That ratio — two required, ~200 provided — is the target.**

### The rule the three systems jointly establish

**Any required contribution whose absence fails *silently* is a contract defect.** Streamlink's
`__plugin__` is the instance: `_load_plugin_from_finder` returns `None` when it is missing or is not a
`Plugin` subclass, and the plugin simply never loads. gallery-dl's registry round-trip is the general
antidote, and it catches the whole class of silent-registration failures at once.

### Ship a required canonical example, checked through the *full* registry

gallery-dl's `test/test_extractor.py`:

```python
extr = cls.from_url(cls.example)
if not extr:
    self.fail(f"{cls.__name__} pattern does not match example URL '{cls.example}'")
self.assertEqual(cls, extr.__class__)
self.assertEqual(cls, extractor.find(cls.example).__class__)   # full-registry round-trip
```

Deterministic count over `gallery_dl/extractor/*.py` (257 modules): **920 `pattern=`, 920 `example=`,
920 registered classes** — exact 1:1, so the pair is de-facto mandatory. `example` doubles as
documentation input (`scripts/supportedsites.py:622`).

Assertion (b), the full-registry leg, is the one that catches a shadowed adapter. A unit test that
constructs the class directly cannot.

## The anti-rule: never derive contract facts from test data

yt-dlp's `_RETURN_TYPE` (`common.py:3822-3832`):

```python
@classproperty(cache=True)
def _RETURN_TYPE(cls):
    """What the extractor returns: "video", "playlist", "any", or None (Unknown)"""
    tests = tuple(cls.get_testcases(include_onlymatching=False))
    if not tests:
        return None
    elif not any(k.startswith('playlist') for test in tests for k in test):
        return 'video'
    elif all(any(k.startswith('playlist') for k in test) for test in tests):
        return 'playlist'
    return 'any'
```

An adapter's **arity** — the single most consequential shape fact about it — is reverse-engineered by
scanning test fixtures for keys beginning `playlist`. It is consumed by `is_single_video()`
(`common.py:3834-3838`), which drives real user-facing behaviour. `age_limit` is derived the same way
(`:3815-3820`).

**Arity is a contract fact. Declare it.** This is the clearest "do the opposite" in the corpus.

## Corollary: do not couple test *data* to the contract, but get the reason right

⚠️ **Premise correction.** gallery-dl migrated in-class `test = (…)` tuples to a separate
`test/results/` tree in three commits over five days (`947a0fc4` publishes the transform script;
`8d3a16c7` adds the exported results; `518768fa` deletes — **171 files, +634 / −9,271**). The dispatch
framed this as a lesson about test/contract coupling. The maintainer's stated motive in issue #4504 is
**runtime import cost first**, verbatim:

> This test data is completely useless for everyone running gallery-dl as a program … **but it still
> gets evaluated and loaded into memory every time gallery-dl is run and imports extractor modules.**
> … It would also waste less CPU cycles and memory when running gallery-dl, **and allow for (easier)
> updates on how these tests are structured.**

The decoupling benefit is the *second* clause. The magnitude argument has since strengthened:
`test/results/` is now **371 files / 43,310 lines** against `gallery_dl/extractor/` at **56,319** — a
test corpus 77 % the size of production code, all of which was formerly in the import path.

**What stayed in the adapter is the single `example` string** — because that is a *contract* fact
(this adapter claims this shape), not a *result* fact. The split reconnects through a direct class
reference (`"#class": telegraph.TelegraphGalleryExtractor`), so a renamed or deleted extractor is an
`ImportError`, not a silently-skipped test.

## Where the contract is actually specified — a warning about prose contracts

gallery-dl's `CONTRIBUTING.md` contains **no** extractor-authoring guidance (14 lines). The de-facto
spec is `scripts/init.py`'s codegen templates plus `test/test_extractor.py`'s contract tests. That is
arguably healthier than yt-dlp's, where the spec is a **475-line docstring** (`common.py:106-580`) and
`CONTRIBUTING.md:288` points authors at *"lines L119-L440"* of it — a citation that has drifted ~140
lines (line 119 is now blank; the docstring runs to 580) and has been stale since 2023-09-23.

**A prose contract has no referential integrity — not even to itself.** Budget for the fact that the
*pointer* to the prose rots too.

## Contract tests worth stealing outright (gallery-dl `test/test_extractor.py`)

- `test_init` — monkeypatches `request` to `self.fail` and calls `initialize()` on **every** registered
  adapter, making "construction does no I/O" an executable invariant rather than a documented one.
  Added (`b4c59993`) after the maintainer himself broke it (issue #6387, breaking AUR package builds).
- `test_names` — asserts class names are mechanically `{Category}{Subcategory}Extractor`.
- `test_docstrings` — asserts every extractor's docstring is unique (they generate the supported-sites
  documentation).
