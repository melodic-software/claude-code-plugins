---
section: acquisition-auth
dispatch_ref: "lead-(a); original-dispatch-(e)"
question: "Does the extractor reliably yield a downloadable video for a public X status, and under what auth/cookie conditions?"
verdict: yes-anonymous-in-steady-state
confidence: high
evidence_tier: verified-firsthand + source + issue-tracker
ytdlp_version: "2026.07.04"
source_identity: "yt_dlp/extractor/twitter.py @ tag 2026.07.04 byte-identical to master (diff exit 0)"
as_of: 2026-08-14
---

# Acquisition and auth

## Headline: the path exists and works without credentials

**Verified firsthand (end-to-end, not a metadata probe).** Full download of a public X status
with no cookies, no account, no extractor args:

```
yt-dlp -f "worst[ext=mp4]/worst" --write-subs --sub-langs all \
  https://twitter.com/LisPower1/status/1001551623938805763
```

Produced a real playable artifact, confirmed by `ffprobe`:

- `dl_test.mp4` — 1,762,361 bytes, `format_name=mov,mp4,m4a,...`, `duration=111.278333`
- video stream `codec_name=h264`, audio stream `codec_name=aac`
- `dl_test.en.vtt` — 8,385 bytes, caption sidecar

This is the only direct evidence in the design that an X acquisition path exists at all.

## Auth model (documented, from source)

| Condition | Behavior | Line |
|---|---|---|
| Logged out (default) | Fetches a guest token from `{_API_BASE}guest/activate.json`, sends `x-guest-token` | L104-127 |
| Logged in | Sends `x-twitter-auth-type: OAuth2Session` + `x-csrf-token` from the `ct0` cookie | L122-126 |
| Login detection | `is_logged_in` = `bool(self._get_cookies(self._API_BASE).get('auth_token'))` | L96-98 |

`_API_BASE = 'https://api.x.com/1.1/'`. Two hardcoded bearer tokens (`_AUTH`, `_LEGACY_AUTH`);
the legacy one is used only when the `legacy` API is selected AND not logged in.

## When cookies ARE required — DOCUMENTED, in source

Three cases only. All raise via `raise_login_required`, which is the signal a cookie-fallback
path should gate on:

1. **NSFW / age-restricted / sensitive** — `reason in ('NsfwLoggedOut', 'NsfwViewerHasNoStatedAge')`
   → `raise_login_required('NSFW tweet requires authentication')` (L1089-1090).
   `NsfwViewerHasNoStatedAge` means an account with no declared birth date is treated as logged-out.
2. **Protected (private) accounts** — `reason == 'Protected'` →
   `raise_login_required('You are not authorized to view this protected tweet')` (L1091-1092).
   **INFERRED-FROM-MAINTAINER** (bashonly, issue #13342, 2025-05-30): the cookie account must also
   *follow* the author; being logged in is not sufficient.
3. **Any API error containing `not authorized`** (case-insensitive) → `raise_login_required` (L140-141).

Corroborated by yt-dlp's own test suite: four cases permanently `'skip': 'Requires authentication'`,
all `'age_limit': 18`; one `'skip': 'Protected tweet'`.

## When cookies are NOT required

Ordinary public posts, in steady state — proven by the firsthand download above and by every
successful probe in this research (all anonymous).

**But guest access is not guaranteed over time.** DOCUMENTED history of site-wide collapse:

| Date | Event |
|---|---|
| 2023-06-30 | X authwalls ALL tweets (#7473, PR #7476 — "In response to Twitter authwalling all tweets") |
| 2023-07-05/06 | Anonymous fallback to legacy API restores guest access |
| 2023-12-24 | `syndication` added as a third anonymous path / 429 fallback (`116c26843`) |
| 2025-03-10 | **Authwall returns** (#12571) — Cloudflare fingerprinting on GraphQL + HTTP 404 |
| 2025-07-25 | **`legacy` API returns 404 — #13837, STILL OPEN** (one anonymous fallback now dead) |
| 2025-12-30 | `a6ba71400` (PR #15432) **removes `-u`/`-p`/`--netrc`** — cookies are now the ONLY auth route |

Both authwall events were fixed with an alternate API, **not** with cookies.

## Extractor args — DOCUMENTED (README is one line)

```
#### twitter
* `api`: Select one of `graphql` (default), `legacy` or `syndication` as the API for tweet
  extraction. Has no effect if logged in
```

That is the entire documented surface. Behavior per value is **maintainer-stated, not documented**
(bashonly, #12571):

- `graphql` — the only method that works with authentication
- `legacy` — no auth; **currently 404ing** (#13837)
- `syndication` — no auth at all (uses `User-Agent: Googlebot` + a locally computed token,
  L1161-1180); **returns only ONE video from multi-video posts**, and loses `*_count` metadata and
  age-restricted content

**INFERRED-FROM-SOURCE (undocumented, no issue reports it):** the "Has no effect if logged in"
caveat is **false for `syndication`**. `_extract_status` L1203-1204 applies syndication
unconditionally *after* the GraphQL call, discarding the authenticated result and wasting a call.

## Rate limiting

- **HTTP 429 is the only signal.** X's API error-code 88 / "Rate limit exceeded" string appears
  nowhere in the tracker in an X context.
- **Since `116c26843` (2023-12-24) a 429 no longer errors** — it warns
  `Rate-limit exceeded; falling back to syndication endpoint` and **silently degrades**. This is a
  correctness hazard, not a failure: a multi-video post silently becomes one video.
- **The guest-token endpoint is the chokepoint.** `_fetch_guest_token` is uncached and fires on
  *every* `_call_api` when logged out (L127). Maintainer-attested (#8532, #8762): datacenter/cloud
  IPs are the dominant trigger; a 429 landed on `guest/activate.json` before any tweet query.
- **No retry, sleep, or backoff exists in the extractor** — verified by source read. Generic
  `--sleep-requests` applies but is **not** maintainer-endorsed for X.
- **NOT RESEARCHED:** actual current request-per-hour budgets. No documented figure exists for X
  (contrast the wiki's YouTube figures). Maintainer-stated guest figures are old and hedged
  ("50 queries per ??? minutes/hours/days", PR #7516).

## Cookie guidance

- **The yt-dlp wiki has NO X section at all** — `grep -rni "twitter|x\.com"` over all 9 wiki pages
  returns zero matches. All cookie guidance is site-agnostic.
- The throwaway-account CAUTION exists **only under YouTube**. Applying it to X is a reasonable
  extrapolation but is **NOT documented guidance**.
- **Account risk from cookies on X is undocumented, not disproven.** Read the absence correctly:
  maintainers apparently do not consider it risky enough to warn about. That is weaker than
  "maintainers state cookies are safe."
- **Operational hazard:** on Windows + Chromium, `--cookies-from-browser` against a live browser
  profile is a **hard force-exit failure** (#7271, #10927, both open), not a warning. Close the
  browser, use `--disable-features=LockProfileCookieDatabase`, or use Firefox.

## Contract implications

1. The anonymous path is the default and it works today — do not require cookies up front.
2. Gate any cookie fallback on `raise_login_required`-shaped errors ONLY (see failure taxonomy).
3. Treat `Rate-limit exceeded; falling back to syndication endpoint` and
   `Not all metadata or media is available via syndication endpoint` on stderr as **silent
   correctness degradation** and surface or fail on them — especially for multi-media posts.
4. Avoid datacenter IPs if throughput matters; there is no in-extractor backoff to lean on.
