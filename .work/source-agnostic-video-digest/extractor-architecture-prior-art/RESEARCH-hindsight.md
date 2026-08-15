---
topic: extractor-architecture-prior-art
section: hindsight
abstract: yt-dlp writes no retrospectives — its regret is expressed as rewrites, and the 2025 PoTokenProvider framework by the same team inverts every design axis of InfoExtractor, which is the closest thing to its own answer to "what would you do differently".
claims:
  - claim: "yt-dlp has GitHub Discussions disabled on both yt-dlp/yt-dlp and ytdl-org/youtube-dl, so no discussion or retrospective corpus exists; design rationale lives only in PR and commit bodies."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "gh api graphql {repository(owner:\"yt-dlp\",name:\"yt-dlp\"){hasDiscussionsEnabled}} -> false"
        tier: 0
        pool: "GitHub API"
      - url: "same query against ytdl-org/youtube-dl -> false"
        tier: 0
        pool: "GitHub API"
  - claim: "No maintainer has ever proposed formalizing the info dict with types, a schema, or validation; the only such request is from a non-maintainer, is open, and has zero comments."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/issues/17229 (open, comments=0)"
        tier: 1
        pool: "yt-dlp issue tracker"
      - url: "gh search issues --repo yt-dlp/yt-dlp on 'info dict schema', 'dataclass extractor', 'TypedDict', 'validate info dict' — no relevant hits"
        tier: 0
        pool: "GitHub API"
  - claim: "yt-dlp's 2025 PoTokenProvider framework, by a current core maintainer, inverts every design axis of InfoExtractor: dataclasses, ABC with abstractmethod, request validation, explicit registration, typed errors, and a declared public API surface."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://github.com/yt-dlp/yt-dlp/pull/12840 (merged 2025-05-18, commit 2685654a)"
        tier: 1
        pool: "yt-dlp maintainers"
      - url: "yt_dlp/extractor/youtube/pot/README.md and pot/provider.py (local checkout @ 5d6b8c8)"
        tier: 0
        pool: "yt-dlp source"
  - claim: "There is no API-stability statement anywhere for the yt-dlp extractor plugin API, while the 2025 provider frameworks lead with an explicit three-module public surface and an internal-only boundary."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "grep for stability language across README.md, CONTRIBUTING.md, yt_dlp/plugins.py, extractor/common.py, the wiki clone, and yt-dlp-sample-plugins — no hits"
        tier: 0
        pool: "yt-dlp source + wiki"
      - url: "yt_dlp/extractor/youtube/pot/README.md:11-22"
        tier: 0
        pool: "yt-dlp source"
  - claim: "yt-dlp's per-extractor network _TESTS are excluded from CI entirely; every workflow runs only the 'core' suite, which expands to pytest -m 'not download'."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "devscripts/run_tests.py:39-62 (local checkout)"
        tier: 0
        pool: "yt-dlp source"
      - url: ".github/workflows/core.yml:117 and quick-test.yml:41"
        tier: 0
        pool: "yt-dlp source"
produced_by: phase-3-preferred-sources
---

# Hindsight — what the extractor contract got wrong

## Method, and a structural finding that reshapes the question

**yt-dlp has GitHub Discussions disabled.** Verified:

```
gh api graphql -f query='{repository(owner:"yt-dlp",name:"yt-dlp"){hasDiscussionsEnabled}}'
→ {"hasDiscussionsEnabled": false}
```

Same for `ytdl-org/youtube-dl`. **There is no discussion corpus, no roadmap thread, and no
retrospective thread.** Design rationale lives in **PR description bodies and commit message bodies**,
which is where every finding below came from.

Second framing caution: **pukkandan** — author of nearly all the architectural work below — is listed
in `Maintainers.md` under *"Inactive Core Maintainers"*. Current core maintainers are coletdjnz,
bashonly, Grub4K.

**yt-dlp's maintainers document problems in PR bodies at the moment they fix them, and almost never
write retrospectives. The regret is expressed as rewrites.**

## 1. The strongest signal: the 2025 provider frameworks are a deliberate re-do

**PR #12840** — *"[ie/youtube] Add a PO Token Provider Framework"*, coletdjnz, merged 2025-05-18
(`2685654a37141cca63eda3a92da0e2706e23ccfd`). Verbatim:

> **Generalisation of the framework outside of the Youtube extractor is out of scope.**
> **Consider this an experiment of a "Extractor Provider" framework. I'm thinking this provides a good
> opportunity to find out how well such a framework works.**

A current core maintainer piloting a **new contract shape** in a contained blast radius, generalization
deliberately deferred pending evidence. Same team, same repo, same problem domain — pluggable per-site
behavior — and every axis inverted:

| Axis | `InfoExtractor` (2008 lineage) | `PoTokenProvider` (2025) |
|---|---|---|
| Contract | 475-line docstring (`common.py:106-580`) | `@dataclasses.dataclass` `PoTokenRequest` / `PoTokenResponse` (`pot/provider.py:45,84`) |
| Base | plain class | `abc.ABC` with `@abc.abstractmethod _real_request_pot` (`:109,196`) |
| Validation | none | `__validate_request`, `__validate_external_request_features` (`:127,164`) |
| Registration | name suffix `IE` + import into `_extractors.py` | explicit `register_provider` / `register_preference` |
| Public surface | undeclared | three named modules; everything else *"internal-only"* |
| Errors | generic `ExtractorError` + `expected` flag | typed `PoTokenProviderError`, `PoTokenProviderRejectedRequest` |

The JS Challenge framework (`yt_dlp/extractor/youtube/jsc/`) follows the identical pattern. Successor
lineage matters too: the PR states it supersedes coletdjnz's out-of-tree plugin `yt-dlp-get-pot` — the
new contract was **prototyped as a plugin, outside the core, before being adopted in-tree.**

**This is yt-dlp's own answer to "what would you do differently," expressed in code rather than prose.**

## 2. The info dict as an untyped contract

The contract is the 475-line docstring at `common.py:106-580`. There is no schema, no `TypedDict`, no
validation. Field drift is visible **in the spec itself** (`common.py:373-382`):

> The following fields are deprecated and should not be set by new code:
> `composer` → Use "composers" instead. `artist` → "artists". `genre` → "genres".
> `album_artist` → "album_artists". `creator` → "creators".

Traced to `104a7b5a46dc1805157fb4cc11c05876934d37c1` (2024-02-20), *"[ie] Migrate commonly plural
fields to lists (#8917)"* — a scalar→list migration across ~940 extractor modules, with both spellings
carried indefinitely because nothing can mechanically find the stragglers.

**Was formalization ever proposed?** Only weakly, only by non-maintainers, and it has gone unanswered:
issue **#17229**, *"Add type hints to `extractor/common.py` and `utils/_utils.py`"* (2026-07-15,
`x5i4k4`), rationale is onboarding not correctness, **open with zero comments**. Searches for
`"info dict schema"`, `"dataclass extractor"`, `"validate info dict"`, `"TypedDict"` returned nothing
relevant.

**Why not (inferred, stated as inference):** the info dict is a **public data format** — it is what
`-J`/`--dump-json` emits and what `--load-info-json` reads back. Formalizing it would freeze an
interface that 940 extractors and every downstream consumer already depend on loosely. The cost is paid
continuously in drift rather than once in a migration.

**Load-bearing artifact: the spec pointer itself has rotted.** `CONTRIBUTING.md:288` sends every new
extractor author to *"[a detailed description of what your extractor should and may return]
(yt_dlp/extractor/common.py#L119-L440)"*. The docstring actually spans **106–580**; line 119 is now
**blank**. Last touched 2023-09-23 by bashonly in *"[cleanup] Misc (#8182)"*. **A prose contract has no
referential integrity, not even to itself** — and nobody noticed, because nothing can notice.

## 3. `_VALID_URL` regex dispatch — pain documented in both directions

Full treatment in `RESEARCH-dispatch.md`. The hindsight-specific items:

- **Over-match**, issue **#13904** *"[cbc.ca] RSS feed URLs shouldn't be matched by extractor"* (open):
  the CBC extractor claims an RSS URL and yields **0** items; `--force-generic-extractor` yields **58**.
  dirkf's fix is to accrete another exclusion into the regex — *"Yes, it seems that
  `podcasting/includes/` (supposing that that characterises the problem feeds) should be excluded as
  initial paths as well as `player/`."* Note the parenthetical: the maintainer is **guessing** at the
  URL shape. That is the treadmill in one sentence.
- **Under-match**, all currently open: #6482 (Viu), #11014 (orf.at), #6407 (srgssr) — all "falls through
  to the generic extractor".
- **The escape hatch was generalized rather than removed.** `--force-generic-extractor` → deprecated
  alias for `--ies generic,default`; superseded by `--use-extractors` (`fe7866d0`, *"Closes #3234,
  Closes #2044"*). **Static ordering could not satisfy everyone, so dispatch order became a user-facing
  runtime knob** — and the selection mechanism is itself regex over extractor *names*.
- **Explicit negative:** seven distinct query phrasings for a host-based-registry proposal returned
  nothing. Combined with Discussions being disabled: **no maintainer has ever publicly proposed
  replacing regex dispatch with host lookup.**

## 4. The plugin API — a significant negative

The contract (README:1989-2057): namespace packages `yt_dlp_plugins.extractor`; discovery **by naming
convention** — *"All public classes with a name ending in `IE`/`PP` are imported from each file"*;
ordering, verbatim — *"Extractor plugins take priority over built-in extractors"*; monkey-patch seam
`class MyPluginIE(ABuiltInIE, plugin_name='myplugin')` which **replaces** the parent
(`common.py:4107-4122`). Safety, verbatim (README:1991):

> Note that **all** plugins are imported even if not invoked, and that **there are no checks** performed
> on plugin code. **Use plugins at your own risk and only if you trust the code!**

**There is no "this API is not stable" statement anywhere.** Greps for
`not stable|unstable|no guarantee|may change|without notice|internal API|breaking change|public api`
across README's PLUGINS section, `CONTRIBUTING.md`, `yt_dlp/plugins.py`, `yt_dlp/extractor/common.py`,
the full wiki clone (`Plugin Development.md` read end to end), and the `yt-dlp-sample-plugins` README
all returned nothing. The README's *"at your own risk"* is about **plugin code being untrusted by the
user**, not about API stability.

Contrast `yt_dlp/extractor/youtube/pot/README.md:11-22`:

> ## Public APIs
> - `yt_dlp.extractor.youtube.pot.cache` / `.provider` / `.utils`
>
> **Everything else is internal-only and no guarantees are made about the API stability.**

**Lesson:** plugin authors are handed a 4,176-line internal base class with **no stated stability
posture at all**. Name the public surface on day one; a plugin ecosystem grown against an undeclared
surface converts every internal refactor into an unbounded compatibility question — which is exactly
the Brightcove problem in #4307, at ecosystem scale.

## 5. `--extractor-args` — no design record, and now unfixable

Full treatment in `RESEARCH-granularity.md`. The hindsight point: commit `5d3a0e79` (2021-06-25) went
**direct to master with a one-line message and no PR** (`gh api .../commits/<sha>/pulls` → empty).
**The mechanism governing per-site behavior across the entire project was introduced with no written
rationale.** No maintainer has publicly called it a mistake, and the pattern is actively expanding.
It cannot be given validation now, because unknown keys have always been silently ignored.

## 6. Tests as part of the contract — demoted out of CI

`_TESTS` live as class attributes; `CONTRIBUTING.md:287` requires at least one per extractor, with a
`skip` reason if untestable. **They are not run in CI.** `devscripts/run_tests.py:39-62`:

```python
if run_core:
    arguments.extend(['-m', 'not download'])
elif run_download:
    arguments.extend(['-m', 'download'])
...
if not run_flaky:                      # run_flaky is False under CI
    arguments.append('--disallow-flaky')
```

Every workflow invokes only `core` — `.github/workflows/core.yml:117`, `quick-test.yml:41` — and `core`
expands to `pytest -m 'not download'`. CI additionally carries `--reruns 2 --reruns-delay 3.0` even on
the non-network suite. The split traces to commit `f2e8dbc` (2022-07-08), body: *"and split download
tests so they can be more easily run in CI / Authored by: coletdjnz"*.

pukkandan on why baked-in network tests decay (#4307):

> the issue is that all the embed tests are currently in GenericIE, listed in no particular order, and
> **a lot of the links are dead**. This makes migrating the tests quite a difficult and time consuming
> process… **it is harder to find new embed tests than finding new extractor tests.**

**Lesson:** separate the two concerns `_TESTS` conflates — **contract conformance** (does this adapter
emit a valid record? offline, fixture-based, CI-gated) and **liveness** (does the real source still
work? network-bound, scheduled, alerting, never on the merge path).

## 7. Other items, and what could NOT be found

- **`common.py` grows monotonically and unremarked:** 3,726 (2022-01-01) → 3,772 → 3,889 → 4,031 →
  **4,176** today, against **940** extractor modules. Searches for `"common.py too large"` /
  `"split common.py"` returned nothing relevant.
- **`_real_extract` / `_real_initialize` / `IE_NAME` / `ie_key` naming:** no maintainer commentary
  exists. *(Structural observation, **inferred**: the `_real_*` prefix exists because the public
  `extract()`/`initialize()` are template methods wrapping the subclass hook — a Template Method whose
  naming leaks the wrapping. And `ie_key()` is a **string** identity used for cross-adapter references,
  `_type: "url"` targets, and `_configuration_arg` keys — adapter identity is a convention-derived
  string, never a type.)*
- **Lazy extractors constrained the contract permanently** — see `RESEARCH-dispatch.md`.
- **The fork rationale is about release velocity, not the contract.** yt-dlp inherited `InfoExtractor`
  essentially unchanged. The one architectural remark is pukkandan's, nine days into the fork (PR #12):
  *"The embed detection in generic extractor is currently **a total mess**… Given how strict the
  youtube-dl devs are about code maintainability, **I have no idea how it got this messed up.**"*

### Explicit negatives — searched and not found

1. GitHub Discussions do not exist for either repo. No discussion corpus, roadmap, or retrospective.
2. No maintainer has ever proposed a typed/validated info dict.
3. No maintainer has ever proposed replacing regex dispatch with a host-based registry.
4. No "the extractor API is not stable" statement exists anywhere for the extractor plugin API.
5. No maintainer criticism of `--extractor-args` as stringly-typed; the pattern is expanding.
6. No maintainer complaint about `common.py`'s size or the base class's scope.
7. No maintainer commentary on `_real_extract`/`_real_initialize`/`IE_NAME`/`ie_key` naming.
8. No discussion thread about network tests in CI — the demotion is visible only in workflow config.

## Peer-system hindsight worth carrying

- **streamlink's in-tree admission** — `src/streamlink/exceptions.py:7`: *"# TODO: don't use PluginError
  for failed HTTP requests or validation schema failures"* (issue #5047). See
  `RESEARCH-result-shape.md`.
- **streamlink's result shape has resisted four years of redesign.** Both overhaul threads are **open
  and unmerged**: #4902 (2022-10) and #5764 (2024-01, locked with *"⚠️ Early work-in-progress ideas"*).
  Stated problem: *"The way streams are returned by plugins, how the stream naming works, how the stream
  weighting/ranking works … are far from ideal. With the advent of the AV1 codec … this will cause lots
  of problems."* **Meanwhile the parts made declarative data — matchers, priority, arguments — shipped,
  deprecated cleanly, and were removed on schedule across 2.3.0 → 8.2.0.** The transferable observation:
  **string-keyed result names (`"1080p60"` parsed by regex, weighed against bitrate via a magic 2.8
  ratio) are a schema you didn't write down, and you cannot migrate one.**
- **streamlink deprecated asymmetrically, on purpose.** `can_handle_url()`/`priority()` were deprecated
  (2.3.0) then removed (6.0.0); `PluginArguments`/`PluginArgument` were **never** deprecated and are
  still exported, because that change was purely additive — *"custom plugins don't need to change
  anything."* **Breaking changes were reserved for what blocked the static-indexing goal.**
- **gallery-dl deprecates at three tiers, with the loudest at the read site:** silent CLI alias
  (`help=SUPPRESS`), silent config fallback (`config2(new, old, default)`), and a **`log.error` at the
  point the removed value would have been read** (`common.py:827-829`). The placement matters — the
  error fires where the setting would have been honored, so it names the right feature.
- **gallery-dl's rule for surviving a contract change that touches every adapter: script the
  transform first.** `947a0fc4` publishes `export_tests.py`; `518768fa` (171 files) runs it and deletes.
  Same pattern for `8fdab9fb` (68 files). Write the transform, run it, then delete.
