# Coverage ledger — extractor-architecture-prior-art

**Corpus bounded?** Partially. The *primary* corpus is bounded and was enumerated before querying:
the six sub-questions in the dispatch × the named anchor system (yt-dlp) plus a contrast set the
dispatch left open-ended ("at least two other mature multi-backend extraction systems"). The contrast
set is therefore **unbounded in practice**; five systems were selected and the selection is recorded
below rather than claimed as exhaustive.

**Enumeration surfaces used:** `git clone` + `git sparse-checkout` of yt-dlp at `5d6b8c8`
(2026-08-04) — Tier 0, exhaustive for the file tree; `grep`/`ls` over that tree for counts;
GitHub PR/issue/commit bodies via `gh api` and `gh search` (Tier 1); full-history clones of gallery-dl
and streamlink by delegated agents.

**Narrowing recorded:** Babel and unified/remark were named as candidate contrast systems in the
dispatch and were **cut** in favour of FFmpeg demuxers, Pygments lexers, and Apache Tika parsers,
because the dispatch's live question was *dispatch arbitration* and those three form a coherent
scored/typed-dispatch contrast family where Babel/unified do not (both dispatch by explicit plugin
list, not by inferring a handler from the input). This is a scoped answer, not an exhaustive survey.

| # | Corpus item | Depth criterion | Done |
|---|---|---|---|
| 1 | `yt_dlp/extractor/common.py` — info-dict docstring (L106-580) | `_type` paragraph set + required-fields paragraph read end to end | [x] |
| 2 | `yt_dlp/extractor/common.py` — class attribute defaults (L580-596) | every class attribute and its default enumerated | [x] |
| 3 | `yt_dlp/extractor/common.py` — dispatch surface (L616-652) | `_match_valid_url`, `suitable`, `_match_id`, `working`, `supports_login` read in full | [x] |
| 4 | `yt_dlp/extractor/common.py` — lifecycle (L654-672, L757-841) | `initialize()` and `extract()` template methods + all 4 hook stubs read in full | [x] |
| 5 | `yt_dlp/extractor/common.py` — result helpers (L1275-1311) | `url_result`, `playlist_result`, `playlist_from_matches` read in full | [x] |
| 6 | `yt_dlp/extractor/common.py` — error helpers (L1246-1274) | `raise_login_required`, `raise_geo_restricted`, `raise_no_formats` read in full | [x] |
| 7 | `yt_dlp/extractor/common.py` — `_RETURN_TYPE` (L3815-3843) | derivation logic read; `is_single_video` consumer traced | [x] |
| 8 | `yt_dlp/extractor/common.py` — embed layer (L4061-4122) | `_extract_from_webpage`, `_extract_embed_urls`, `StopExtraction`, `__init_subclass__` read in full | [x] |
| 9 | `yt_dlp/extractor/common.py` — `_configuration_arg` + `_yes_playlist` (L4023-4051) | both read in full | [x] |
| 10 | `yt_dlp/YoutubeDL.py` — dispatch loop (L1677-1726) | `extract_info` matching loop read end to end | [x] |
| 11 | `yt_dlp/extractor/twitter.py` — `TwitterIE._real_extract` arity branches (L1330-1391) | all five 0/1/N branches read and tabulated | [x] |
| 12 | `yt_dlp/utils/_utils.py` — exception taxonomy | every `*Error` class name enumerated | [x] |
| 13 | `devscripts/make_lazy_extractors.py` + `extractor/extractors.py` | ordering assertions located and quoted | [x] |
| 14 | Dispatch-cost counts across `yt_dlp/extractor/` | `suitable()` overrides, cross-extractor calls, lookahead files, module count — all four computed by grep | [x] |
| 15 | yt-dlp PR #4307 (embed framework) | motivation list + before/after line counts | [x] |
| 16 | yt-dlp PR #12840 + `youtube/pot/README.md` | new-contract axes + stability statement quoted | [x] |
| 17 | yt-dlp plugin API surface (README PLUGINS, wiki, CONTRIBUTING, `plugins.py`) | searched for a stability statement; absence recorded | [x] |
| 18 | yt-dlp CI config (`run_tests.py`, `core.yml`, `quick-test.yml`) | `_TESTS`-not-in-CI claim settled from the config | [x] |
| 19 | gallery-dl `extractor/common.py` + `extractor/__init__.py` + `message.py` | base class, registry, message enum read in full | [x] |
| 20 | streamlink `plugin/plugin.py` + `session/plugins.py` + `exceptions.py` | contract, priority algorithm, exception taxonomy read in full | [x] |
| 21 | FFmpeg `libavformat/format.c` probe loop + score constants | scoring/tie-break arithmetic read in full | [x] |
| 22 | Pygments `lexer.py` + `lexers/__init__.py` + `_mapping.py` | two-stage dispatch and tie-break rankers read in full | [x] |
| 23 | Apache Tika `Parser`/`Detector`/`CompositeParser`/`MimeTypes` (3.3.2) | interfaces + detection precedence + fallback read in full | [x] |
| 24 | Babel plugin system | **CUT** — see narrowing note above | [ ] |
| 25 | unified/remark plugin system | **CUT** — see narrowing note above | [ ] |

**Ledger status: 23 of 25 marked; rows 24-25 explicitly cut with reason recorded, not silently
skipped.** Coverage of the bounded primary corpus (rows 1-23) is complete.

## Falsification queries run

| Hypothesis under test | Falsifying query | Result |
|---|---|---|
| "`_VALID_URL` regex dispatch is the right shape and beats a host registry" | grep the tree for the *cost* of regex dispatch: `suitable()` overrides, cross-extractor `suitable()` calls, negative-lookahead `_VALID_URL`s | **Falsified as stated.** 74/88/54 respectively; `YoutubeIE.suitable()` dispatches on the query string, a dimension the regex cannot model. Regex dispatch degrades into a hand-written registry |
| "yt-dlp maintainers considered and rejected host-based dispatch" | `gh search issues` on seven phrasings (`host based extractor`, `domain based dispatch`, `extractor registry`, `replace regex extractor matching`, `wrong extractor matched`, `extractor order precedence`, `netloc`) | **Absence, not rejection.** No such proposal exists. GitHub Discussions are disabled on the repo (`hasDiscussionsEnabled: false`), so there is no discussion corpus at all |
| "yt-dlp would design `InfoExtractor` the same way today" | search for a newer first-party plugin framework by the same team | **Falsified.** `PoTokenProvider` (PR #12840, 2025) inverts every axis: dataclasses, ABC, validation, explicit registration, typed errors, declared public surface |
| "The gallery-dl `test/` migration was about test/contract coupling" | read the originating issue (#4504) rather than inferring from the diff | **Premise corrected.** Stated motive is runtime import cost first; evolvability second |
| "streamlink matcher `priority` exists so third-party plugins override built-ins" | read `session/plugins.py:133-169` and count non-default priorities in the plugin tree | **Falsified.** Override is module-name shadowing, a separate mechanism. Only 2 of 135 plugins use non-default priority, both generic catch-alls |
