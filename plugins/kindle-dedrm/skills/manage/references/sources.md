# Upstream source inventory

Every URL this skill depends on, with purpose, drift signal, and last-fetched fingerprint. The `update` action walks this file and reports which sources drifted.

## Primary tutorial

| Field | Value |
|---|---|
| URL | `https://techy-notes.com/drm-removal-from-kindle-ebook-purchases-old-method/` |
| Purpose | Procedural source of truth — exact step ordering, plugin names, current Key_Finder zip URL |
| Drift signal | Page body diff |
| Last-fetched | 2026-05-10 (at the prior URL) |
| Last-fetched key claims | (a) Kindle for PC 2.8.0(70980) is the only working version; (b) DeDRM_tools v10.0.14+ pre-release required; (c) Kindle_Key_Finder 2026.04.28.JH zip is current; (d) KFX Input plugin from Calibre's "Get new plugins" catalog |

Upstream moved 2026-07 (re-probed 2026-07-19): the prior URL `remove-drm-from-kindle-ebooks/` now returns HTTP 404. Its successor is inferred to be `drm-removal-from-kindle-ebook-purchases-old-method/` (the site relabeled the Kindle-for-PC + KFXKeyExtractor approach the "OLD Method" and returns HTTP 200 for that slug) — NOT read-confirmed as the same procedure, because the article is now subscriber-gated. The `update` action can therefore no longer walk the public body for the current Key_Finder zip URL; it HEAD-probes the pinned direct zip URL in `references/versions.md` instead. Propagate any new pin there. See the epubor secondary below and the MSIX-successor note when the OLD Method finally breaks.

## Secondary tutorial (cross-check)

| Field | Value |
|---|---|
| URL | `https://www.epubor.com/kindle-kfx-key-extractor-download-and-how-to-extract-key-from-kindle-kfx.html` |
| Purpose | Cross-check the techy-notes procedure; alternative if techy-notes goes down |
| Drift signal | Page body diff |
| Last-fetched | 2026-05-10 |
| Last-fetched key claims | (a) Kindle for PC 2.8.0–2.8.3 supported; (b) DeDRM v10.0.18 referenced (older than Satsuoni's current pre-release); (c) KFX Input v2.31.0; (d) KFXArchiver283.exe + manual command-line invocation pattern |

Reference material when techy-notes diverges. Lower priority for drift action.

## Kindle for PC installer

| Field | Value |
|---|---|
| URL | `https://kindleforpc.s3.amazonaws.com/70980/KindleForPC-installer-2.8.70980.exe` |
| Purpose | The pinned 2.8.0.70980 binary |
| Drift signal | HTTP HEAD non-200 (Amazon revoked) |
| Last-fetched | 2026-05-10 (HTTP 200, 285 MB) |
| Auth | None — public S3 bucket |

If Amazon revokes the URL, this skill is significantly compromised — alternate mirror required (web.archive.org is one option, but binary availability isn't guaranteed). Document any alternate mirror in `references/versions.md` with provenance notes.

## DeDRM_tools (Satsuoni fork)

| Field | Value |
|---|---|
| Repo | `https://github.com/Satsuoni/DeDRM_tools` |
| Releases API | `https://api.github.com/repos/Satsuoni/DeDRM_tools/releases` |
| Purpose | DeDRM_plugin.zip + KFX extractors |
| Drift signal | Latest pre-release tag differs from `references/versions.md` pin |
| Last-fetched | 2026-05-10 |
| Last-fetched latest tag | `v10.0.20` (pre-release, asset `DeDRM_tools.zip`) |
| Auth | None for public read |

`gh api repos/Satsuoni/DeDRM_tools/releases` (jq filtered) returns the live release list. Fork ships pre-releases as the user-facing channel — most recent `prerelease: true` tag is the one to pin.

## Kindle_Key_Finder zip

| Field | Value |
|---|---|
| URL pattern | `https://techy-notes.com/content/files/<YYYY>/<MM>/Kindle_Key_Finder_<YYYY.MM.DD>.JH.zip` |
| Discovered via | Pinned direct URL (article-body discovery lost to paywall — see below) |
| Purpose | Phase orchestrator that bundles tools + Python phases |
| Drift signal | HEAD-probe of the pinned direct zip URL (non-200 = revoked/rolled) |
| Last-fetched URL | `https://techy-notes.com/content/files/2026/04/Kindle_Key_Finder_2026.04.28.JH.zip` (still serving byte-identical zip, SHA-verified 2026-07-19) |

Date in URL rolls forward when the author publishes a new build. The original `update` approach — WebFetch the tutorial article, regex `Kindle_Key_Finder_\d{4}\.\d{2}\.\d{2}\.JH\.zip`, compare against the pinned filename — no longer works: the article is subscriber-gated as of 2026-07 (see Primary tutorial), so its public body carries no zip link. The drift check now HEAD-probes the pinned direct URL instead; roll-forward to a NEW build requires a subscriber to read the current article and update the pin by hand.

## Calibre

| Field | Value |
|---|---|
| URL | `https://calibre-ebook.com/download` |
| Purpose | E-book manager; host for plugins |
| Drift signal | None tracked (Calibre updates frequently and is forward-compatible with the plugins) |

Calibre version not pinned. User installs latest. If a future Calibre release breaks the plugin contract, document in `references/troubleshooting.md`.

## Python

| Field | Value |
|---|---|
| URL | `https://www.python.org/downloads/` |
| Purpose | Runtime for Kindle_Key_Finder phase scripts |
| Drift signal | None tracked (any Python ≥ 3.6 works; standard library only) |

Avoid Microsoft Store version (sandboxed, blocks file access). `Run_keyfinder.bat` filters this out automatically.

## Drift report format

`scripts/check-drift.sh` produces output like:

```text
[OK]      Kindle for PC installer URL          (HEAD 200, 285 MB unchanged)
[OK]      DeDRM_tools latest pre-release       (v10.0.20 == pinned)
[OK]      Kindle_Key_Finder zip URL            (HEAD 200 on pinned direct URL; roll-forward discovery paywalled)
[OK]      Tutorial article body                (page hash unchanged)
[STALE]   Tool support matrix                  (utils.py adds 2.9.2 — KFXARCHIVER_TOOL_MAP grew)
```

User then decides:

- For `STALE` entries → confirm re-pin → skill re-downloads + updates `versions.md`
- For `UNREACHABLE` entries → manual research; possibly find alternate source

## How to add a new source

When this skill grows to track a new upstream (e.g., a Frida-based extractor for Kindle 3.x that doesn't exist yet):

1. Add a row to this file with URL + purpose + drift signal.
2. Add a probe to `scripts/check-drift.sh` that returns `OK` / `STALE` / `UNREACHABLE`.
3. If the source has a version, pin it in `references/versions.md`.
4. Reference it from the relevant action in `SKILL.md`.
