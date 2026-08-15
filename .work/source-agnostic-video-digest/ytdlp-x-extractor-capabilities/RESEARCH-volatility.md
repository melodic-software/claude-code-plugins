---
section: volatility
dispatch_ref: "lead-(f); original-dispatch-(g)"
question: "How volatile is this extractor — breakage frequency and what typically breaks it?"
verdict: ~11x-more-stable-than-youtube-by-frequency; but-long-tail-and-capabilities-get-retired-not-repaired
confidence: high
evidence_tier: scripted-aggregation-over-full-clone + issue-tracker
ytdlp_version: "2026.07.04"
as_of: 2026-08-14
---

# Extractor volatility

Method: full `git clone --filter=blob:none` of yt-dlp/yt-dlp (23,948 commits, 139 tags), all
aggregation **scripted** over `git log`, issues via authenticated `gh api`. Clone currency verified
against the API (`origin/master = 5d6b8c8cd, 2026-08-04`). No rate limits bit.

Independently corroborated: `twitter.py` at tag **2026.07.04 is byte-identical to master**
(`diff` exit 0) — nothing has changed in the file in ~6 weeks.

## Commit frequency

"Raw" = every commit touching the path. "Focused" = ≤10 files (strips repo-wide ruff/cleanup
sweeps). "X-scoped" = subject prefixed `[ie/twitter…]`/`[extractor/twitter…]`, excluding the
periscope/vine commits that share the file.

| Year | raw | focused | X-scoped |
|---|---|---|---|
| 2021 | 5 | 2 | 2 |
| 2022 | 12 | 8 | 8 |
| 2023 | 21 | 19 | **18** |
| 2024 | 10 | 7 | 7 |
| 2025 | 10 | 10 | 8 |
| 2026 (thru 08-14, partial) | 4 | 4 | 3 |
| **Total** | **62** | **50** | **46** |

2023 is the outlier — the Musk-era API lockdown. Post-2023 the file runs 7–8 X-scoped commits/year,
trending down.

**Gaps, last 24 months:**

| Measure | any touch | X-scoped |
|---|---|---|
| Commits in window | 16 | 14 |
| Distinct active months | 10 of 24 | **9 of 24** |
| **Median gap** | **26 d** | **34.5 d** |
| p90 gap | 110 d | — |
| **Longest gap** | **219 d** | 219 d |
| Current open gap | 57 d | **66 d** (since `7edb5ee87`, 2026-06-09) |

## Breakage taxonomy

Hand-assigned single primary class over the 46 X-scoped commits, after reading diffs for the
ambiguous ones.

| Class | Count | Share |
|---|---|---|
| (a) X-side API/GraphQL endpoint, query-id, or response-shape change | 14 | 30% |
| (b) auth / guest-token / bearer / login / syndication-token | 10 | 22% |
| (c) URL pattern / domain (twitter.com → x.com, onion) | 3 | 7% |
| (d) format / variant / metadata extraction | 14 | 30% |
| (e) new feature, extractor removal, tests-only | 5 | 11% |

**Do not read a winner off the ranking** — (a) and (d) tie at 14, and at N=46 they are not
separable (e.g. `7edb5ee87` moved `view_count` from `mediaStats.viewCount` to `views.count`: an
X-side shape change presenting as a metadata fix). The robust aggregate:

> **Breakage-driven (a+b+c) = 27/46 = 59%. Enhancement/metadata (d+e) = 41%.**

**The era shift is the decision-relevant part:**

| Era | a | b | c | d | e | n |
|---|---|---|---|---|---|---|
| 2021–2022 | 2 | 2 | 1 | 3 | 2 | 10 |
| 2023 | **9** | 2 | 0 | 6 | 1 | 18 |
| 2024–2026 | 3 | **6** | 2 | 6 | 3 | 20 |

2023 was raw API churn. **Since 2024 what breaks is auth-adjacent** — syndication-token generation
(twice: #12107, #12537), cookie/login handling (#13024), and eventually login deleted outright.

## Issue velocity

yt-dlp has a `site:youtube` label but **no twitter/x equivalent**, so title search is the only
symmetric comparison.

| Query | Count |
|---|---|
| `is:issue twitter in:title` (all time) | 131 |
| `is:issue x.com in:title` (all time) | 12 |
| `is:issue is:open twitter in:title` | **18** |
| `label:site-bug twitter in:title` | 65 |
| `twitter in:title created:>=2025-01-01` | 35 |

**3 most recent significant breakages:**

| Issue | Opened | Title | Fix | Open→fix | Open→release |
|---|---|---|---|---|---|
| #15963 | 2026-02-16 | `Error(s) while querying API: Dependency: Unspecified` | `0d8898c3f` | **2 d** | 5 d |
| #15998 | 2026-02-19 | same error (regression from the above fix) | `77221098f` | **0 d** | 2 d |
| #15402 | 2025-12-25 | single video link treated as playlist, `--no-playlist` ignored | `ce9a3591f` | **4 d** | 35 d |

**These medians are survivorship-biased** — they cover only issues carrying a `Closes` trailer.
The honest counterweight, open as of 2026-08-14:

| Open issue | Age | Labels |
|---|---|---|
| #9715 Unpredictable behaviour following links in Tweets | **848 d** | site-bug, patch-available |
| #11937 Intermittent "Failed to parse JSON" | **594 d** | site-bug, cant-reproduce |
| #13837 Legacy API returns 404 | **385 d** | site-bug, needs-investigating |
| #14664 Downloads quoted tweet despite `--no-playlist` | 299 d | site-bug |
| #16585 [CNN][twitter] circular redirection | 109 d | site-bug |
| #17243 Cannot download from protected accounts despite cookies | 28 d | site-bug, triage |

> **The single most decision-relevant data point is not a median.** Issue **#12616** (login fails /
> flags account suspicious, opened 2025-03-15) took **289 days to "fix" and 320 days to reach a
> release — and the fix was `[ie/twitter] Remove broken login support`.** X breakages are not always
> repaired; sometimes the capability is deleted.

## Time-to-released-fix

| Cohort | Issue→fix commit | Issue→release tag |
|---|---|---|
| All 33 `Closes`-linked twitter issues (2021–2026) | median **6 d**, max **372 d** | median **29 d**, max **395 d** |
| 2024+ subset (n=10) | median **3 d**, max **289 d** | median **11 d**, max **320 d** |

Release cadence adds a second term: tag gaps since 2024 are median **10 d**, max **84 d**.

**Compound worst case for a pinned-release consumer:** X breaks → up to ~290 d for a fix on master
→ up to ~84 d for a tag → your own upgrade interval. Observed worst end-to-end: **320 days**.
Typical: 11 days.

## Comparison anchor: YouTube

Path union of `yt_dlp/extractor/youtube.py` (499 commits, pre-split) and `yt_dlp/extractor/youtube/`
(148), deduped = 646.

| Year | YouTube raw | YouTube focused | twitter raw | twitter focused |
|---|---|---|---|---|
| 2021 | 176 | 160 | 5 | 2 |
| 2022 | 168 | 140 | 12 | 8 |
| 2023 | 73 | 65 | 21 | 19 |
| 2024 | 69 | 63 | 10 | 7 |
| 2025 | 116 | 111 | 10 | 10 |
| 2026 (partial) | 44 | 42 | 4 | 4 |
| **Total** | **646** | **581** | **62** | **50** |

Cleanest single measure, last 24 months:

| | YouTube | twitter.py | Ratio |
|---|---|---|---|
| **Median inter-commit gap** | **3 d** | **26 d** (34.5 X-scoped) | **~9× (~12×)** |
| Max gap | 43 d | **219 d** | 0.2× |
| Distinct active months | ~24/24 | 10/24 | — |

Issue volume since 2025-01-01: `youtube in:title` = **653**; `twitter`+`x.com in:title` = **38**
(**~17×**).

## Contract implications

1. **X is the MORE stable of the two adapters by frequency** — ~11.6× fewer commits, ~17× fewer
   issues than YouTube. Do not budget X breakage-tolerance by analogy to YouTube's cadence.
2. **But it fails differently.** YouTube breaks often and is fixed within days by a large maintainer
   bench; X breaks rarely, and when it does the tail is long — a 219-day commit silence, six
   site-bugs open 28–848 days, and at least one capability retired rather than repaired.
3. **Size fallback windows off the tail (weeks-to-months) for anything auth-dependent**, not off the
   3-day median. Auth-adjacent is precisely where the 2024+ breakage mass sits.
4. **Pin the release channel deliberately.** `--update-to nightly` collapses the largest
   controllable term (the tag wait: median 10 d, max 84 d).
