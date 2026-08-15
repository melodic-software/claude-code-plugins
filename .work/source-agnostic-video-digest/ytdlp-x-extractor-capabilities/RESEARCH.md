---
topic: ytdlp-x-extractor-capabilities
status: complete
confidence: high
sidecar_count: 6
ytdlp_version: "2026.07.04"
source_identity: "yt_dlp/extractor/twitter.py @ tag 2026.07.04 is byte-identical to master (diff exit 0)"
live_probing: performed (public posts only; one full download)
acquisition_path_exists: true
as_of: 2026-08-14
sidecars:
  - file: RESEARCH-acquisition-auth.md
    dispatch_ref: "lead-(a)"
    verdict: yes-anonymous-in-steady-state
  - file: RESEARCH-captions.md
    dispatch_ref: "lead-(b)"
    verdict: best-effort-absent-more-often-than-present; no-date-cutoff
  - file: RESEARCH-playlist-shape.md
    dispatch_ref: "lead-(c)"
    verdict: playlist-iff-2-or-more-entries; zero-entry-is-downstream-artifact
  - file: RESEARCH-id-semantics.md
    dispatch_ref: "lead-(d)"
    verdict: display_id-is-the-join-key; id-is-usually-the-media-id
  - file: RESEARCH-failure-taxonomy.md
    dispatch_ref: "lead-(e)"
    verdict: only-2-of-12-classes-cookie-remediable
  - file: RESEARCH-volatility.md
    dispatch_ref: "lead-(f)"
    verdict: 11x-more-stable-than-youtube; long-tail-risk
  - file: RESEARCH-word-tags.md
    dispatch_ref: "original-dispatch-(b)"
    verdict: undocumented-but-real; ytdlp-does-not-strip
---

# yt-dlp X/Twitter extractor — capabilities and limits

Baseline **yt-dlp 2026.07.04** (installed). `yt_dlp/extractor/twitter.py` at that tag is
**byte-identical to master**, so every source claim holds for both. Line numbers throughout the
sidecars refer to that file.

## Headline for the design

**The X acquisition path exists and works anonymously.** Verified firsthand end-to-end, not by
metadata probe: a full download of a public status with no cookies produced a playable
`1,762,361`-byte MP4 (`h264` + `aac`, `duration=111.278333`, confirmed by `ffprobe`) plus its
caption VTT sidecar. Given that nothing else in the repository acquires X media, this is the
evidence that the path is viable at all.

## Contract obligations, ranked

| # | Obligation | Sidecar |
|---|---|---|
| 1 | Anonymous acquisition is the default and works; require cookies only on `raise_login_required` | acquisition-auth |
| 2 | **Gate the cookie fallback on `raise_login_required` only** — none of the three observed X errors is auth | failure-taxonomy |
| 3 | Reject any result whose `extractor` != `twitter` — the off-platform chase silently returns foreign media | failure-taxonomy |
| 4 | Key the slice on `(display_id, id)`; `display_id` is the only stable status-id field | id-semantics |
| 5 | Do not fail closed on `entries == []` — read `playlist_count` | playlist-shape |
| 6 | A caption rung cannot assume coverage; ASR fallback is required | captions |
| 7 | Use `--convert-subs srt` or parse `<X-word-ms>` deliberately — yt-dlp does not strip it | word-tags |
| 8 | Size auth-dependent fallback windows in weeks-to-months, not days | volatility |

## Corrections to the dispatch's stated premises

1. **The URL's status id is reported as `display_id`, not `id`.** `id` is usually the *media* id.
2. **Subtitle keys are not always `en`** — `en-US`, `en-GB` observed; `und` reachable.
3. **A zero-entry playlist is not an extractor state** — it is a downstream YoutubeDL artifact
   (reproduced with `-I 5`; `playlist_count` survives as the discriminator).
4. **`<X-word-ms>` has a closing tag and wraps the word text**, and the dispatch's sample
   (`ms=120,180 … character_ranges=0-5`) has an arity mismatch that never occurs in real output —
   it does not match any captured X data.
5. **Caption availability has no date cutoff in either direction**, and neither does the word-tag
   markup. Both are per-video properties of X's pipeline.

## Answers in brief

- **(a) Acquisition/auth** — Works anonymously for ordinary public posts. Cookies are required for
  exactly three things (NSFW/age-restricted, protected accounts, `not authorized`), all surfacing
  via `raise_login_required`. Cookies are now the *only* auth route (credential login deleted
  2025-12-30). A 429 does not error — it silently degrades to the syndication endpoint, losing
  metadata and all but one video of a multi-video post.
- **(b) Captions** — The extractor is a pure pass-through for HLS `#EXT-X-MEDIA:TYPE=SUBTITLES`;
  no twitter-specific caption code exists, and `automatic_captions` is never populated. The
  pre-2024 gap is **resolved**: a **2018** post carries `en` captions while multiple 2024–2026 posts
  carry none, so no date cutoff exists. Captions were absent more often than present in sampling.
- **(c) Playlist shape** — `_type: playlist` iff `len(entries) >= 2`; a single-video post returns a
  plain video dict. Entries merge full post metadata. A zero-entry playlist is downstream-only.
- **(d) ID semantics** — `display_id` is always the URL status id; `id` is the media id for
  `extended_entities`/`unified_card` videos and the status id for card/vmap videos; the playlist
  container has the status id and **no** `display_id`. Retweets replace the entire status with the
  original (source-derived); quote-tweets concatenate the quoted post's media (verified, issue
  #14664 open).
- **(e) Failure taxonomy** — 12 classes enumerated with exact strings; all three dispatch-observed
  strings reproduced firsthand, including `No video formats found!`, whose trigger is a
  `summary_large_image` card falling through to the vmap branch and fabricating an empty-format
  entry.
- **(f) Volatility** — ~11.6× fewer commits and ~17× fewer issues than YouTube; median
  inter-commit gap 26 d vs 3 d. But the tail is long: a 219-day silence, six site-bugs open
  28–848 days, and one capability retired rather than repaired.

## Evidence labelling

Every claim in the sidecars is marked as one of:

- **DOCUMENTED** — quoted from yt-dlp source, README, wiki, or an issue/PR with a number.
- **VERIFIED FIRSTHAND** — I ran it on this machine against public posts on 2026.07.04.
- **INFERRED-FROM-SOURCE** / **INFERRED-FROM-MAINTAINER** — a direct reading or a maintainer
  statement, not independently reproduced.
- **NOT RESEARCHED** — stated explicitly rather than filled in.

## Known gaps (stated, not filled)

- **What predicts caption presence** on a given X video — the `ext_tw_video` vs `amplify_video`
  hypothesis was tested and fails. No observable predictor found.
- **What predicts `<X-word-ms>` presence** — both the "auto-generated track" and "recent track"
  hypotheses were falsified firsthand. An `en` vs `en-XX` correlation holds at n=4 but is
  contradicted by one third-party report.
- **Retweet behavior not probed live** — the L1206 status-replacement reading is source-derived.
- **All-entries-failed playlist not constructed** — only the filtering mechanism for `entries: []`
  was reproduced.
- **Current X rate-limit budgets** — no documented figure exists for X; maintainer figures are old
  and self-hedged.

---

## Parent-side rows (written by the dispatching session)

### Verifier verdict — ACCEPT with three corrections

Verified independently against source by a context independent of this producer.

**Confirmed, and stronger than reported:**

- **Off-platform ingestion (`:1381`) is complete PROVENANCE SUBSTITUTION**, not "merged metadata".
  The `info` payload (`:1222-1238`) carries `id` (= `twid`), `title` prefixed with the **tweet
  author's** name, `description`, `uploader`, `uploader_id`, `uploader_url`, `channel_id`,
  `timestamp`, and all four engagement counts. A foreign video arrives wearing the tweet's identity.
  Issue **#9715 confirmed real and open** (2024-04-18). The `extractor != 'twitter'` mitigation is
  **checkable as written**, because `url_result` yields `_type: 'url'` and the final `extractor`
  field is the foreign one.
- **Retweet semantics promoted from source-derived to VERIFIED without a live probe.** `:1206`
  returns the original tweet's status object wholesale, while `twid` comes from the URL (`:1214`) and
  `display_id=twid` is set on every return path — so `display_id` is the URL status id even for a
  retweet while every content field belongs to a different post.
- `display_id` = URL status id confirmed on all three return paths. `id` = media id confirmed via
  `_TESTS` fixtures that repeatedly differ and occasionally match — **so the hedge "usually the media
  id" is correct and must not be tightened.**

**Corrections:**

1. **The acquisition verdict overreaches.** One anonymous download proves *the path exists today*, not
   *steady state* — and the same artifact documents guest access collapsing site-wide **twice**.
   Rename the verdict to **`anonymous-works-today; plan for periodic collapse`**. Obligations 1 and 8
   already concede this (obligation 8's weeks-to-months fallback sizing only makes sense if the steady
   state is unstable), so the artifact currently contradicts itself.
2. **The caption sampling claim needs its n stated and must not be quoted as a rate.** n=12, 4
   present / 8 absent — but **biased toward presence**: at least three of the four caption-positive
   posts are yt-dlp's own `_TESTS` fixtures, chosen precisely because they exercise caption handling.
   True absence rate is likely **higher**. Direction safe, number not.
3. **Rest the ASR obligation on UNPREDICTABILITY, not frequency.** The artifact establishes firmly
   that captions are sometimes absent and that **no predictor exists** — structurally (no date, size,
   or version gate in the code path) and empirically (the `ext_tw_video` vs `amplify_video`
   hypothesis tested and falsified). That argument does not depend on a rate at all and is
   unassailable; the frequency framing inherits the sampling weakness for no benefit.

**On `<X-word-ms>`:** the correction is right — X's own `xai-org/x-algorithm` regex requires the
closing tag — but record it as a **lossy handoff sample, not a prior-session error**. Truncating a
ten-value `ms=` list and dropping a closing tag is what a summary does. Two of that session's other
observations have since been independently confirmed from source.

**Not reproduced by the verifier, flagged as reported-not-verified:** the firsthand download itself,
the twelve-post caption sampling, and the `xai-org/x-algorithm` regex quote.

### Project fit

This lane selects its adapter **from a user-supplied URL**, which makes two findings bind harder here
than they would elsewhere:

- The off-platform hazard is not a curiosity — it is the **primary correctness risk** of adding a
  source whose posts routinely link off-platform. The `extractor` check is a contract obligation.
- The 429-silent-degradation path (loses `*_count` metadata and **all but one video of a multi-video
  post**, with no retry or backoff in the extractor) means the adapter must **detect degradation
  rather than trust a returned result**. A silent partial slice is worse than a failed one for a
  pipeline whose output feeds research and synthesis.
