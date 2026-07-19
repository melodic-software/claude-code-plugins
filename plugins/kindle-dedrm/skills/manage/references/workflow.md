# Full setup workflow

Long-form version of `/kindle-dedrm:setup apply`. Each step lists the exact command, rationale, and how to verify success. Walk through this with the user, pausing at every checkpoint.

Captured 2026-05-10 against Kindle for PC 2.8.0.70980, DeDRM_tools v10.0.20, Kindle_Key_Finder 2026.04.28.JH.

## Pre-flight (agent-side, no user action)

Run `scripts/status.sh` and confirm:

| Probe | Required state for `setup` |
|---|---|
| Calibre installed | yes (any recent version) |
| Python on PATH | yes (3.6+, not WindowsApps stub) |
| pwsh available | yes (PowerShell 7.x or 5.x both work) |
| Existing Kindle for PC install | absent OR exactly 2.8.0.70980 |
| Existing firewall rule | absent (will be created) |
| Existing ICACLS deny | absent (will be applied) |
| `~/Tools/Kindle_Key_Finder` | absent (will be created) |

If a non-2.8.0 Kindle for PC is installed, user must uninstall it first (Settings → Apps → Amazon Kindle → Uninstall). Skill does NOT auto-uninstall — that's destructive and reversible damage.

## Step 1 — Download three artifacts

Land in `~/Downloads/` for predictability + retention. SHA256 verify against `references/versions.md`.

```bash
mkdir -p ~/Downloads && cd ~/Downloads

curl -L -o KindleForPC-installer-2.8.70980.exe \
  "https://kindleforpc.s3.amazonaws.com/70980/KindleForPC-installer-2.8.70980.exe"

# Resolve the latest Satsuoni pre-release tag dynamically. Requires the
# authenticated `gh` CLI (declared in the plugin README). When gh is absent or
# the query returns nothing, fall back to the REAL pinned tag: before running
# this block, read the DeDRM_tools tag out of references/versions.md (the
# `releases/download/<tag>/DeDRM_tools.zip` asset row) and substitute it for
# PINNED_TAG_FROM_VERSIONS_MD below. The guard refuses to continue with the
# placeholder still in place, so a malformed URL can never be composed.
LATEST_TAG=$(gh api repos/Satsuoni/DeDRM_tools/releases --jq '[.[] | select(.prerelease == true)][0].tag_name // empty' 2>/dev/null || true)
if [[ -z "${LATEST_TAG}" || "${LATEST_TAG}" == "null" ]]; then
  LATEST_TAG="PINNED_TAG_FROM_VERSIONS_MD" # substitute the literal tag, e.g. v10.0.20
  if [[ "${LATEST_TAG}" == "PINNED_TAG_FROM_VERSIONS_MD" ]]; then
    echo "gh unavailable and no pinned tag substituted — read it from references/versions.md, then rerun." >&2
    exit 1
  fi
  echo "gh unavailable — using pinned DeDRM tag ${LATEST_TAG} from references/versions.md"
fi
curl -L -o "DeDRM_tools-${LATEST_TAG}.zip" \
  "https://github.com/Satsuoni/DeDRM_tools/releases/download/${LATEST_TAG}/DeDRM_tools.zip"

# Kindle_Key_Finder zip: use the pinned direct URL from references/versions.md.
# The former article-body discovery is dead — the tutorial is subscriber-gated
# as of 2026-07 (see references/sources.md), so a new build's URL can only be
# obtained by a subscriber reading the current article and re-pinning by hand.
# This block runs from ~/Downloads, so no relative path can reach the plugin's
# references directory. Before running, substitute the absolute path of the
# versions.md that sits next to this workflow file (the same file the DeDRM
# fallback above reads) for VERSIONS_MD_ABS_PATH. The guard refuses to continue
# with the placeholder still in place.
VERSIONS_MD="VERSIONS_MD_ABS_PATH"
if [[ "${VERSIONS_MD}" == "VERSIONS_MD_ABS_PATH" || ! -f "${VERSIONS_MD}" ]]; then
  echo "versions.md path not substituted or not found — set VERSIONS_MD to the absolute path of references/versions.md, then rerun." >&2
  exit 1
fi
ZIP_URL=$(awk '/^## Kindle_Key_Finder/{s=1} s&&/^\| Captured URL \|/{if(match($0,/`[^`]+`/)){print substr($0,RSTART+1,RLENGTH-2);exit}}' \
  "${VERSIONS_MD}")
if [[ -z "${ZIP_URL}" ]]; then
  echo "Key_Finder URL not found in references/versions.md — repair the pin, then rerun from this step." >&2
  exit 1
fi
curl -L -o "$(basename "$ZIP_URL")" "$ZIP_URL"

sha256sum KindleForPC-installer-2.8.70980.exe DeDRM_tools-*.zip Kindle_Key_Finder_*.JH.zip
```

Verify hashes against `references/versions.md`. If hashes diverge, **stop and re-fetch** — Amazon binaries do not legitimately change at a fixed version pin; a hash mismatch means the binary changed (either Amazon repackaged or URL now serves something different) and you should investigate before running it.

## Step 2 — Extract DeDRM_tools and Kindle_Key_Finder

```bash
cd ~/Downloads
mkdir -p "DeDRM_tools-${LATEST_TAG}" && (cd "DeDRM_tools-${LATEST_TAG}" && unzip -o "../DeDRM_tools-${LATEST_TAG}.zip")

mkdir -p ~/Tools
unzip -o ~/Downloads/Kindle_Key_Finder_*.JH.zip -d ~/Tools/Kindle_Key_Finder
```

Expected after extract:

```text
~/Downloads/DeDRM_tools-v10.0.20/
  DeDRM_plugin.zip          (load this into Calibre)
  KFXKeyExtractor28.exe
  KFXArchiver291.exe
  ... (others not used)

~/Tools/Kindle_Key_Finder/
  Run_keyfinder_admin.vbs   (launch this)
  Run_keyfinder.bat
  key_finder.py
  code/
    tools/                  (KFXKeyExtractor282, KFXArchiver283, KFXArchiver291)
    phases/                 (Python phase scripts)
    modules/                (config, utils)
```

## Step 3 — User runs Kindle for PC installer (interactive)

Cannot drive UAC + EULA programmatically. Tell the user:

```text
Run: ~/Downloads/KindleForPC-installer-2.8.70980.exe
- UAC prompt: Yes
- EULA: Accept
- Install location: default
- After install: do NOT open Kindle yet
```

**CHECKPOINT — wait for user confirmation that installer completed.**

Verify install:

```bash
powershell.exe -NoProfile -Command "(Get-Item '${LOCALAPPDATA}\Amazon\Kindle\application\Kindle.exe').VersionInfo | Select-Object FileVersion"
```

Expect `2.8.0.70980`. If anything else, installer ran an upgrade (see `references/troubleshooting.md` "Installed wrong Kindle for PC version").

## Step 4 — Sign-in race window (CRITICAL)

Highest-risk window in the entire workflow. Amazon stages a 2.9.x installer aggressively when Kindle.exe phones home. Firewall block from step 7 stops the download, but at this point we don't have it in place yet — sign-in REQUIRES network access, so we accept a small race window.

Before the user opens Kindle, brief them with:

```text
1. Open Kindle for PC.
2. If you see ANY upgrade prompt → REFUSE (close window via X if no skip option).
3. Sign in with your Amazon account.
4. Click Sync (cloud icon top-left).
5. Library appears. Double-click each book you want to download.
6. Wait for the "New" overlay to clear (downloaded checkmark).
7. Quit Kindle entirely (File → Exit). Verify no tray icon.
```

**CHECKPOINT — wait for user confirmation that books synced and Kindle is quit.**

Verify books on disk:

```bash
ls -la "${USERPROFILE}/Documents/My Kindle Content/" | head -30
ls "${USERPROFILE}/Documents/My Kindle Content/" | grep -c "_EBOK"
```

Each `_EBOK` directory is one book. Spot-check one:

```bash
ls "${USERPROFILE}/Documents/My Kindle Content/$(ls ${USERPROFILE}/Documents/My\ Kindle\ Content/ | grep _EBOK | head -1)/"
```

Should contain `*.azw`, `*.voucher`, `*.azw.md`, `*.azw.res`. Voucher file holds the encrypted DRM key; .azw is the encrypted book content.

## Step 5 — Apply firewall block

Now we lock down. User opens admin PowerShell and runs:

```powershell
New-NetFirewallRule -DisplayName "Block Kindle for PC (lock 2.8.0)" -Direction Outbound -Action Block -Program "$env:LOCALAPPDATA\Amazon\Kindle\application\Kindle.exe" -Profile Any -Enabled True
```

Or via this skill's wrapper:

```bash
pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/firewall.ps1" -Action enable
```

Verify:

```powershell
Get-NetFirewallRule -DisplayName "Block Kindle for PC (lock 2.8.0)" | Format-List Name, Action, Enabled, Direction
```

Expect `Action: Block, Enabled: True, Direction: Outbound`.

## Step 6 — Delete cached installer + apply ICACLS deny

If sign-in already triggered an update download, an installer will sit at `%LOCALAPPDATA%\Amazon\Kindle\updates\KindleForPC-installer.exe`. Delete it, then deny write on the directory so Kindle can't re-download.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/manage/scripts/lock-updates.sh" apply
```

Internally this:

```bash
rm -f "${LOCALAPPDATA}/Amazon/Kindle/updates/KindleForPC-installer.exe"
powershell.exe -NoProfile -Command "icacls '${LOCALAPPDATA}\Amazon\Kindle\updates' /deny '${USERDOMAIN}\${USERNAME}:(W,WD,AD,WA)'"
```

Verify:

```bash
touch "${LOCALAPPDATA}/Amazon/Kindle/updates/test-write" && echo "LOCK FAILED" || echo "LOCK OK"
```

Expect `LOCK OK` (Permission denied).

## Step 7 — Install Calibre plugins (user-driven GUI)

Cannot drive Calibre's plugin UI programmatically. Tell the user:

```text
Open Calibre.

Plugin 1 — KFX Input:
1. Preferences → Plugins (Advanced section)
2. Click "Get new plugins"
3. Filter: "KFX Input"
4. Select → Install → Yes (security warning)
5. Restart Calibre when prompted

Plugin 2 — DeDRM:
1. After restart: Preferences → Plugins
2. Click "Load plugin from file"
3. Yes (security warning)
4. Navigate to ~/Downloads/DeDRM_tools-v10.0.20/
5. Select DeDRM_plugin.zip → Open
6. Yes (install)
7. Restart Calibre

Verify: Preferences → Plugins → expand "File type plugins" → see both KFX Input and DeDRM (multiple entries).
```

**CHECKPOINT — wait for user confirmation that both plugins loaded and Calibre restarted.**

## Step 8 — Run keyfinder

Quit Calibre completely (keyfinder writes to Calibre's `dedrm.json` and conflicts if Calibre is running).

User double-clicks `~/Tools/Kindle_Key_Finder/Run_keyfinder_admin.vbs`. UAC → Yes.

First-run wizard prompts (defaults are fine):

```text
- Kindle Content Path: %USERPROFILE%\Documents\My Kindle Content (default)
- Privacy obfuscation: user choice
- Display options: defaults
- Calibre integration: enable (auto-import + EPUB convert)
- Confirm: Yes
```

Tool runs four phases in order:

1. **Phase 1 — Key extraction.** Runs KFXKeyExtractor28.exe per book; falls back to KFXArchiver283.exe for unsupported versions. Writes `~/Tools/Kindle_Key_Finder/Keys/kindlekey.txt` + `kindlekey.k4i`.
2. **Phase 2 — DeDRM config.** Reads keys, writes them to `%APPDATA%\calibre\plugins\dedrm.json`.
3. **Phase 3 — Calibre import.** Uses `calibredb add` per book; DeDRM strips encryption on import.
4. **Phase 4 — KFX → EPUB conversion.** Uses `ebook-convert` per book.

**CHECKPOINT — wait for user confirmation that all 4 phases completed without errors.**

Console output is verbose. If any book fails, tool prints a per-book summary at end. Failed books typically reflect Kindle version mismatches (e.g., a book downloaded by 2.9.x won't decrypt with 2.8.x keys).

## Step 9 — Verify EPUBs

```bash
find "${USERPROFILE}/Calibre Library/" -name "*.epub" | grep -v "Quick Start"
```

Expect one EPUB per book under `<author>/<title> (N)/`. Spot-check by opening one in Calibre or a third-party EPUB reader.

## Done

State checklist after successful setup:

- `Kindle.exe` reports `2.8.0.70980`
- Firewall rule `Block Kindle for PC (lock 2.8.0)` exists, enabled, blocks outbound
- ICACLS deny applied to `%LOCALAPPDATA%\Amazon\Kindle\updates`
- `~/Tools/Kindle_Key_Finder/` populated with phase scripts + tools + saved config
- `~/Downloads/{KindleForPC-installer-2.8.70980.exe, DeDRM_tools-v10.0.20*, Kindle_Key_Finder_*.JH.zip}` retained for re-runs
- Calibre has KFX Input + DeDRM plugins loaded
- Calibre `dedrm.json` populated with extracted keys
- `%USERPROFILE%\Calibre Library\` has DRM-stripped EPUBs of every synced book

This state is precondition for `sync` mode (no further setup needed for new books).
