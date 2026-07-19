# Captured version pins

Versions, URLs, and SHA256 hashes verified working on 2026-05-10. The `update` action diffs upstream against these. Treat each row as a Tier 0 fact at the date captured; verify before re-using.

## Kindle for PC

| Field | Value |
|---|---|
| Pinned version | `2.8.0.70980` |
| Installer URL | `https://kindleforpc.s3.amazonaws.com/70980/KindleForPC-installer-2.8.70980.exe` |
| SHA256 | `2ed64ee0fb5ad94032d6d9824d4efbeeea435255c963e9393d949259b87ebfa4` |
| File size | 285 MB (298,242,024 bytes) |
| Captured | 2026-05-10 |

Why this version: KFXKeyExtractor hard-codes memory offsets for Kindle for PC builds 2.8.0 / 2.8.1 / 2.8.2. KFXArchiver supports up to 2.8.3 + 2.9.1. 2.8.0.70980 is the oldest Amazon still serves directly via the S3 path; older versions were revoked. Newer versions (2.8.3+) still work with KFXArchiver but Amazon revoked those S3 URLs as of capture date — 2.8.0.70980 is the last installer re-fetchable without finding a third-party mirror.

Auto-update behavior: Kindle.exe phones home on launch and stages newer installer at `%LOCALAPPDATA%\Amazon\Kindle\updates\KindleForPC-installer.exe`, then auto-runs it on next launch. Mitigation: firewall rule (this skill installs) plus ICACLS deny on the `updates/` dir.

Observed staged update during 2026-05-10 setup: `2.9.1.71006`. Captured installer hash not retained (deleted as part of normal workflow).

## DeDRM_tools (Satsuoni fork)

| Field | Value |
|---|---|
| Pinned tag | `v10.0.20` |
| Pre-release | yes (Satsuoni's fork ships pre-releases as the user-facing channel) |
| Asset URL | `https://github.com/Satsuoni/DeDRM_tools/releases/download/v10.0.20/DeDRM_tools.zip` |
| SHA256 | `c908be142934a7a030d890ba023ba32becc4f8ef4637bd42d8efdcef90b3f2d2` |
| File size | 1.1 MB (1,112,576 bytes) |
| Asset date | 2026-04-18 |
| Captured | 2026-05-10 |

Repo: `https://github.com/Satsuoni/DeDRM_tools` — fork of the original NoDRM/Apprentice Harper DeDRM_tools, maintained specifically for compatibility with current Kindle for PC / KFX format. Upstream `noDRM/DeDRM_tools` is also viable but lags this fork on KFX support.

Asset contents (verified 2026-05-10):

```text
DeDRM_plugin.zip            (Calibre plugin to install)
DeDRM_plugin_ReadMe.txt
KFXArchiver291.exe          (Kindle 2.9.1 fallback extractor)
KFXKeyExtractor28.exe       (Kindle 2.8.x primary extractor)
KFXKeyExtractor282.exe      (alternate name for same)
kindleFridaInstr.py         (Frida-based extraction for newer Kindle)
KRFKeyExtractor.exe         (KRF key extractor)
Obok_plugin.zip             (Kobo DRM removal — different ecosystem)
obok_plugin_ReadMe.txt
ReadMe_Overview.txt
```

For `kindle-dedrm`, only `DeDRM_plugin.zip` is consumed directly (loaded into Calibre via "Load plugin from file"). The `.exe` files are also bundled inside `Kindle_Key_Finder` so usually not needed from this archive.

## Kindle_Key_Finder (techy-notes.com)

| Field | Value |
|---|---|
| Pinned filename | `Kindle_Key_Finder_2026.04.28.JH.zip` |
| URL pattern | `https://techy-notes.com/content/files/<YYYY>/<MM>/Kindle_Key_Finder_<YYYY.MM.DD>.JH.zip` |
| Captured URL | `https://techy-notes.com/content/files/2026/04/Kindle_Key_Finder_2026.04.28.JH.zip` |
| SHA256 | `0a55b58ad3953eed6b6a2e81bf6a4c053b7d08c420a5d622ab3c14f8a208d46d` |
| File size | 1.8 MB (1,878,035 bytes) |
| Internal version label | `2026.04.28.JH` (date-based, no semver) |
| Captured | 2026-05-10 |

Author rolls the URL forward periodically (date in filename + path matches build date). The `update` action's drift check walks the article body at `https://techy-notes.com/remove-drm-from-kindle-ebooks/` and extracts the current download link rather than guessing the next date.

Bundled tools (verified 2026-05-10):

```text
code/tools/KFXArchiver283.exe      (Kindle 2.8.0 / 2.8.1 / 2.8.2 / 2.8.3)
code/tools/KFXArchiver291.exe      (Kindle 2.9.1)
code/tools/KFXKeyExtractor282.exe  (Kindle 2.8.x — supports 2.8.0 / 2.8.1 / 2.8.2)
```

Phase scripts (Python 3.6+, standard library only — no pip install required):

```text
phase_01_key_extraction.py     (run KFXKeyExtractor + KFXArchiver, write Keys/)
phase_01_alt_extraction.py     (Mode B: KFXArchiver-only path)
phase_02_dedrm_config.py       (write keys to Calibre's dedrm.json)
phase_03_calibre_import.py     (calibredb import)
phase_03_calibre_import-msi-crosshair.py  (alternate import path)
phase_03_alt_import.py
phase_04_epub_conversion.py    (KFX → EPUB via ebook-convert)
```

Launchers:

```text
Run_keyfinder.bat              (auto-elevates via UAC if non-admin)
Run_keyfinder_admin.vbs        (canonical admin launcher — recommended)
key_finder.py                  (entry point if running Python directly)
```

## Tool support matrix

KFXKeyExtractor + KFXArchiver hard-code memory offsets for specific Kindle for PC builds. Any Kindle version outside the supported list causes the extractor to crash with `STATUS_ACCESS_VIOLATION (0xC0000005)`. From `code/modules/utils.py` in Kindle_Key_Finder 2026.04.28.JH:

```python
SUPPORTED_KINDLE_VERSIONS = ['2.8.0', '2.8.1', '2.8.2']           # KFXKeyExtractor
SUPPORTED_KINDLE_VERSIONS_ALT = ['2.8.0', '2.8.1', '2.8.2', '2.8.3', '2.9.1']  # KFXArchiver

KFXARCHIVER_TOOL_MAP = [
    (['2.8.0', '2.8.1', '2.8.2', '2.8.3'], 'kfxarchiver283'),  # KFXArchiver283.exe
    (['2.9.1'],                              'kfxarchiver291'),  # KFXArchiver291.exe
]
```

Mode A (default) = try KFXKeyExtractor first, fall back to KFXArchiver. Mode B (force_alt) = KFXArchiver only — useful on 2.8.3+.

## Calibre

| Field | Value |
|---|---|
| Minimum supported | 9.x (per techy-notes.com, captured 2026-05-10) |
| Latest verified | latest at user's OS (Windows 11) |
| Plugin storage | `%APPDATA%\calibre\plugins\` |
| DeDRM key store | `%APPDATA%\calibre\plugins\dedrm.json` |
| Library default | `%USERPROFILE%\Calibre Library\` |

Plugin install paths (after Calibre sees them):

```text
%APPDATA%\calibre\plugins\KFX Input.zip       (or jhowell variant)
%APPDATA%\calibre\plugins\DeDRM.zip
%APPDATA%\calibre\plugins\dedrm.json          (key store written by phase_02)
```

## Python

| Field | Value |
|---|---|
| Minimum | 3.6 (per Kindle_Key_Finder README) |
| Verified | 3.14.4 |
| Resolution | Run_keyfinder.bat skips WindowsApps stubs and PythonSoftwareFoundation sandbox installs; accepts python.org / uv installs |

Keyfinder excludes the WindowsApps stub (App Execution Alias) and the Microsoft Store sandbox install (`PythonSoftwareFoundation` packages folder). Confirm via `where python` — first non-stub result wins.

## How to refresh this file

When the `update` action surfaces drift:

1. Update the affected row in this file (new tag, new SHA256, new URL).
2. Update `references/sources.md` if the URL pattern itself changed.
3. Re-run `setup` (or just the affected portion) to pull the new artifact.
4. Verify SHA256 matches the new pin before continuing.
5. Run a single-book sync to confirm extraction still works.
