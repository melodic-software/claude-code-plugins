---
name: kindle-dedrm
description: "Manage the Kindle for PC 2.8.0 + Calibre DeDRM workflow for personal-use ebook DRM removal on books you own (Windows only). Action router: setup (first-time install — download, firewall block, ICACLS lock, Calibre plugins, keyfinder), sync (new purchases — disable firewall, sync Kindle, re-enable, re-run keyfinder), update (drift check — upstream version pins and tutorial URLs, no mutations), cleanup (reversible decommission — per-item confirmation, --soft or --full), status (diagnostic). Every state mutation has a documented compensating reversal. Use when: \"set up Kindle DRM removal\", \"remove DRM from Kindle books\", \"extract keys from my Kindle library\", \"sync new Kindle books I bought\", \"check if DeDRM setup is current\", \"clean up Kindle DRM tools\", \"undo DeDRM setup\", \"convert Kindle books to EPUB\", Calibre + Kindle mentioned together, or making Kindle library readable on a non-Kindle device."
argument-hint: "[setup|sync|update|cleanup|status] [--dry-run] [--soft|--full]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Personal-use Kindle DRM removal is a fragile multi-tool workflow with state mutations that, if forgotten, leave the user's machine in an awkward state (silent auto-update, stuck firewall rules, half-installed Calibre plugins). This skill captures the lifecycle as discrete reversible actions and tracks every upstream source that drifts independently (Amazon's Kindle for PC release cadence, Satsuoni's DeDRM_tools fork, Kindle_Key_Finder zip with rolling date in URL, techy-notes.com tutorial article).

Scope: Windows-only (Kindle for PC + KFXKeyExtractor are Windows binaries). Single-user. Books the user owns.

## Pre-computed context

Probe current state on every invocation. Run scripts/status.sh and read the JSON output before deciding which action applies.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/status.sh"
```

Output reports: Kindle for PC version, firewall rule presence, ICACLS deny presence, ~/Tools/Kindle_Key_Finder presence, ~/Downloads installer presence, Calibre install presence, Calibre plugin presence (best-effort), book count in My Kindle Content + Calibre Library.

## Action router

| Action | When | What it does |
|---|---|---|
| (empty) | Default — auto-detect from status | If pristine → recommend `setup`. If state OK + user mentioned new books → recommend `sync`. Otherwise emit status report |
| `setup` | First-time install | Full provisioning: download, install Kindle for PC 2.8.0, sign-in checkpoint, sync books, install Calibre plugins, run keyfinder, apply firewall + ICACLS lockdown |
| `sync` | New books purchased after initial setup | Disable firewall, prompt user to sync in Kindle, delete cached installer, re-enable firewall, re-run keyfinder |
| `update` | Periodic drift check | WebFetch tutorial URLs + gh API for upstream releases, diff against captured baselines in `references/sources.md`, emit drift report. No mutations |
| `cleanup` | Decommission | Walk through every reversible mutation with per-item Y/N. Default (confirm-each) offers the firewall rule, ICACLS deny, keyfinder, and downloads; `--soft` limits to tools + downloads (keeps the firewall/ICACLS lock and Kindle for PC); `--full` also offers to uninstall Kindle for PC and remove Calibre plugins. The Calibre Library is never offered |
| `status` | Diagnostic | Same as default empty action |

Smart auto-detect when action is empty: read pre-computed context, classify state, recommend the most-fitting action OR emit status if classification is ambiguous. Never commit to setup/sync/cleanup without user confirmation when ambiguous.

## Hard safety rules

Apply across every action. Violating any risks losing the working 2.8.0 setup or stranding the user with an upgraded Kindle that can't be downgraded without re-extracting from a different machine.

- **Never open Kindle for PC while the firewall block is disabled UNLESS the user is actively syncing new books AND has the keyfinder ready to run immediately afterward.** Amazon stages 2.9.x installers aggressively; one open window with internet access is enough to cache an installer that auto-runs on next launch.
- **Never run the cached installer at `%LOCALAPPDATA%\Amazon\Kindle\updates\KindleForPC-installer.exe`.** This is the auto-update payload that breaks key extraction. Delete it whenever it appears.
- **Never recommend `--no-confirm` flags or batch-confirm cleanup.** Each reversal is independent; some harder to redo than others (re-pinning Kindle 2.8.0 is easy; re-syncing 50 books isn't).
- **Never send any of these scripts, keys, or extracted files outside the user's machine.** Personal-use scope only.
- **The cached installer + firewall race is real:** if user reports "an installer popped up when I opened Kindle," immediately follow scripts/sync-finalize.sh delete logic. Do not let the installer complete.

## Action: setup

First-time installation walkthrough. Reads `references/workflow.md` for full step-by-step.

High-level sequence:

1. **Verify prerequisites:** Calibre installed (any recent version), Python 3.6+ on PATH (not WindowsApps stub), pwsh available, admin rights available.
2. **Download three artifacts** to `~/Downloads/` and verify SHA256 against `references/versions.md`:
   - `KindleForPC-installer-2.8.70980.exe` from kindleforpc.s3.amazonaws.com (version-pinned URL)
   - `DeDRM_tools.zip` (latest pre-release tag) from `gh release` on `Satsuoni/DeDRM_tools`
   - `Kindle_Key_Finder_<rolling-date>.JH.zip` from techy-notes.com
3. **Extract** DeDRM_tools to `~/Downloads/DeDRM_tools-<tag>/`, Kindle_Key_Finder to `~/Tools/Kindle_Key_Finder/`.
4. **User runs Kindle for PC installer** interactively (UAC + EULA prompts; agent cannot drive these).
5. **CHECKPOINT — sign-in race window.** Before opening Kindle for PC, advise user: refuse any update prompt, sign in, sync, double-click each book to download, quit Kindle entirely.
6. **Verify books on disk** under `%USERPROFILE%\Documents\My Kindle Content\` (look for `_EBOK` directories with `.azw` + `.voucher`).
7. **Apply firewall block** via `scripts/firewall.ps1 enable` (admin pwsh).
8. **Delete cached installer + apply ICACLS deny** via `scripts/lock-updates.sh apply`.
9. **Install Calibre plugins** — user-driven GUI work (Calibre Preferences → Plugins → Get new plugins → KFX Input; Load plugin from file → DeDRM_plugin.zip from extracted DeDRM_tools).
10. **Run keyfinder** — user double-clicks `~/Tools/Kindle_Key_Finder/Run_keyfinder_admin.vbs`. Tool walks first-run config wizard then runs all 4 phases (key extraction → DeDRM config → Calibre import → KFX→EPUB conversion).
11. **Verify EPUBs** in `%USERPROFILE%\Calibre Library\<author>\<title>\*.epub`.

Do NOT proceed past step 4 without user confirmation that installer completed without auto-update being clicked. Pause at step 5 and remind user of the sign-in race window before they open Kindle.

Detailed commands, exact paths, and rationale: see `references/workflow.md`.

## Action: sync

Re-sync new books purchased after initial setup. Idempotent — safe to re-run.

```bash
# Dry-run preview first
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/sync-prep.sh" --dry-run
```

Sequence:

1. Verify state via status.sh — abort if firewall rule absent or ICACLS deny missing (run `setup` first).
2. **Disable firewall block** (`scripts/firewall.ps1 disable`).
3. **User opens Kindle for PC, syncs, double-clicks new books, quits Kindle.** Agent cannot drive GUI; pause for user confirmation.
4. **Delete any newly-staged installer** at `%LOCALAPPDATA%\Amazon\Kindle\updates\*` (`scripts/sync-finalize.sh delete-cache`). ICACLS deny prevents *future* writes but doesn't stop one that lands during the brief firewall-disabled window.
5. **Re-enable firewall block** (`scripts/firewall.ps1 enable`).
6. **Re-run keyfinder** (`~/Tools/Kindle_Key_Finder/Run_keyfinder_admin.vbs`). Saved config auto-loads; tool processes only new books.
7. **Verify new EPUBs** under Calibre Library.

If user reports a cached installer popped up during step 3, that's expected — Amazon staged 2.9.x. Delete it via step 4 immediately and verify Kindle.exe still reports 2.8.0.70980.

## Action: update

Drift check. No mutations. Diffs upstream sources against captured baselines in `references/sources.md` + `references/versions.md`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/check-drift.sh"
```

Sources monitored:

| Source | Drift signal | Captured baseline |
|---|---|---|
| `kindleforpc.s3.amazonaws.com/70980/KindleForPC-installer-2.8.70980.exe` | HEAD request returns non-200 | URL pinned in `references/versions.md`; alternate mirror needed if revoked |
| `github.com/Satsuoni/DeDRM_tools` releases | Newest pre-release tag differs from baseline | Last-known-good tag in `references/versions.md` |
| `techy-notes.com/remove-drm-from-kindle-ebooks/` article body | Page hash differs (URL re-fetch + diff) | Last-fetched body summary in `references/sources.md` |
| `techy-notes.com/content/files/<YYYY>/<MM>/Kindle_Key_Finder_<YYYY.MM.DD>.JH.zip` | Date in URL rolled forward | Last-known URL pattern in `references/versions.md` |
| `epubor.com` companion article | Page hash differs | Secondary reference; lower priority |
| KFXKeyExtractor / KFXArchiver supported Kindle versions (in Key_Finder source) | New entry in `code/modules/utils.py` `KFXARCHIVER_TOOL_MAP` | Captured in `references/versions.md` |

Output: drift report listing each source's status (`current` / `stale` / `unreachable`) and recommended action (`re-download` / `update version pin` / `manual review`). User decides what to act on; update action itself does not apply changes.

When the user accepts a drift recommendation:

1. Apply the change to the relevant `references/*.md` file (update pin, refresh page summary).
2. Run the affected portion of `setup` (e.g., re-download DeDRM_tools if a new pre-release is selected).
3. Verify the workflow still works end-to-end on at least one book (run `sync` mode against a single test book).

## Action: cleanup

Reverse every mutation made by this skill. Per-item confirmation by default.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/cleanup.sh"           # confirm-each (default)
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/cleanup.sh --soft"    # tools + downloads only
bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/cleanup.sh --full"    # everything including Kindle for PC + Calibre plugins
```

Reversal matrix (every row maps a mutation made by setup/sync to its compensating reversal):

| Mutation | Compensating reversal | Confirm by default? |
|---|---|---|
| Windows Firewall rule "Block Kindle for PC (lock 2.8.0)" | `Remove-NetFirewallRule -DisplayName "Block Kindle for PC (lock 2.8.0)"` | Yes |
| ICACLS deny on `%LOCALAPPDATA%\Amazon\Kindle\updates` | `icacls "<path>" /remove:d "<user>"` | Yes |
| `~/Tools/Kindle_Key_Finder/` directory | `rm -rf` | Yes |
| `~/Tools/Kindle_Key_Finder/key_finder_config.json` (saved prefs) | Removed with directory above | Implicit |
| `~/Downloads/KindleForPC-installer-2.8.70980.exe` | `rm` | Yes |
| `~/Downloads/DeDRM_tools-v*.zip` + extracted dir | `rm -rf` | Yes |
| `~/Downloads/Kindle_Key_Finder_*.JH.zip` | `rm` | Yes |
| Cached installer at `%LOCALAPPDATA%\Amazon\Kindle\updates\*` | `rm` (lock removed first if --full) | Yes |
| Kindle for PC install (`%LOCALAPPDATA%\Amazon\Kindle\application\`) | `uninstall.exe` (interactive) | Only on `--full` |
| Calibre KFX Input plugin | Manual via Calibre Preferences → Plugins | Only on `--full`, GUI step |
| Calibre DeDRM plugin | Manual via Calibre Preferences → Plugins | Only on `--full`, GUI step |
| Calibre `dedrm.json` (key store) | `rm "$APPDATA\calibre\plugins\dedrm.json"` | Only on `--full` |
| Calibre Library books (decrypted EPUBs) | NEVER auto-deleted; user keeps these | Manual only, never offered |

The skill should NEVER offer to delete the user's Calibre Library — those are the decrypted books the entire workflow exists to produce.

## What this skill does NOT do

- Modify books the user does not own. Workflow only processes content already present in `My Kindle Content/`.
- Distribute extracted EPUBs anywhere off the user's machine.
- Bypass updates the user explicitly requests (if user says "I want to upgrade to Kindle 2.9.x", this skill cleanly disengages via `cleanup --full`).
- Touch other Amazon services or Kindle hardware. Kindle for PC only.
- Mock around with the cached installer at the Amazon binary level (we delete, we don't patch).
- Run on Mac/Linux. KFXKeyExtractor + KFXArchiver are Windows binaries with hard-coded memory offsets.

## Cross-references

- `references/workflow.md` — procedural detail (the long-form version of `setup`)
- `references/sources.md` — URL inventory + drift baselines + page hashes
- `references/versions.md` — version pins, SHA256 baselines, supported Kindle/tool matrix
- `references/troubleshooting.md` — common errors and recovery paths
- `scripts/` — executable helpers cited above

## Recheck triggers

| Condition | Action |
|---|---|
| Amazon revokes Kindle for PC 2.8.0.70980 from S3 | Find alternate mirror; update `references/versions.md`; widen the supported version pin if a newer version still works with KFXKeyExtractor |
| Satsuoni archives the DeDRM_tools repo | Find current maintained fork; update repo URL in `references/sources.md` |
| techy-notes.com tutorial 404s or moves | Pivot to epubor.com tutorial (secondary); update `references/sources.md` |
| Kindle for PC ships a version > 2.9.1 not in `KFXARCHIVER_TOOL_MAP` | Wait for KFXArchiver update; document in `references/troubleshooting.md` |
| Calibre's KFX Input plugin renamed in catalog | Update plugin name reference in `references/workflow.md` |
| User reports a sync that left a 2.9.x cached installer past firewall re-enable | Tighten timing in `scripts/sync-prep.sh` — possibly add an automatic `sync-finalize.sh` invocation when Kindle.exe quits |
