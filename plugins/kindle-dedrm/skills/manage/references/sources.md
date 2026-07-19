# Upstream source inventory

Every URL this skill depends on, with purpose, drift signal, and last-fetched fingerprint. The `update` action walks this file and reports which sources drifted.

## Primary tutorial

| Field | Value |
|---|---|
| URL | `https://techy-notes.com/remove-drm-from-kindle-ebooks/` |
| Purpose | Procedural source of truth — exact step ordering, plugin names, current Key_Finder zip URL |
| Drift signal | Page body diff |
| Last-fetched | 2026-05-10 |
| Last-fetched key claims | (a) Kindle for PC 2.8.0(70980) is the only working version; (b) DeDRM_tools v10.0.14+ pre-release required; (c) Kindle_Key_Finder 2026.04.28.JH zip is current; (d) KFX Input plugin from Calibre's "Get new plugins" catalog |

The `update` action re-fetches this URL via WebFetch and compares against "Last-fetched key claims" above. If version pin or zip URL changes, propagate to `references/versions.md`.

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
| Discovered via | Tutorial article body (techy-notes.com primary) |
| Purpose | Phase orchestrator that bundles tools + Python phases |
| Drift signal | Article body links a different filename / date |
| Last-fetched URL | `https://techy-notes.com/content/files/2026/04/Kindle_Key_Finder_2026.04.28.JH.zip` |

Date in URL rolls forward when author publishes a new build. `update` action approach: WebFetch tutorial article, regex for `Kindle_Key_Finder_\d{4}\.\d{2}\.\d{2}\.JH\.zip`, compare against pinned filename in `references/versions.md`.

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
[STALE]   Kindle_Key_Finder zip URL            (article body: Kindle_Key_Finder_2026.06.15.JH.zip; pinned: 2026.04.28.JH)
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
