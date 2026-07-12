# Troubleshooting

Symptoms encountered (or expected) during setup / sync / cleanup, with diagnosis and recovery.

## Installed wrong Kindle for PC version

**Symptom:** `Kindle.exe` reports any version other than `2.8.0.70980` after setup. Usually `2.9.x` because:

1. Pre-existing Kindle for PC was installed and the 2.8.0 installer ran in upgrade mode.
2. User clicked "Update" on a prompt during sign-in, OR the cached installer at `%LOCALAPPDATA%\Amazon\Kindle\updates\` ran on next launch.

**Diagnosis:**

```powershell
(Get-Item "$env:LOCALAPPDATA\Amazon\Kindle\application\Kindle.exe").VersionInfo | Select-Object FileVersion
```

**Recovery:**

1. Uninstall the current version: Settings → Apps → Amazon Kindle → Uninstall. OR run `%LOCALAPPDATA%\Amazon\Kindle\application\uninstall.exe`.
2. Re-run the 2.8.0.70980 installer from `~/Downloads/`.
3. If the firewall rule wasn't in place when this happened, re-apply it BEFORE opening Kindle this time.
4. Re-sync books (they may need to re-download since uninstall clears `My Kindle Content/`).

## Cached installer popped up when opening Kindle

**Symptom:** User opens Kindle (with firewall block in place) and an installer dialog appears — "Install Kindle for PC" or similar.

**Diagnosis:** Installer downloaded BEFORE firewall block applied (typical sign-in race window). Now auto-running on launch. Kindle.exe firewall block doesn't stop the installer because installer is a separate process.

**Recovery:**

1. **Do NOT click anything in the installer dialog. Do NOT click Cancel.** Leave it open.
2. Verify the installer hasn't already run:

   ```powershell
   (Get-Item "$env:LOCALAPPDATA\Amazon\Kindle\application\Kindle.exe").VersionInfo.FileVersion
   ```

   If still `2.8.0.70980` → not run, you're safe to proceed. If `2.9.x` → already upgraded; follow "Installed wrong Kindle for PC version" above.

3. Identify the installer process and kill it:

   ```powershell
   Get-Process | Where-Object { $_.Path -like "*KindleForPC-installer*" }
   # Note the Id, then:
   Stop-Process -Id <pid> -Force
   ```

4. Delete the cached installer:

   ```bash
   rm -f "${LOCALAPPDATA}/Amazon/Kindle/updates/KindleForPC-installer.exe"
   ```

5. If the ICACLS deny isn't already applied, apply it now:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/lock-updates.sh" apply
   ```

## Keyfinder fails with "Calibre is running"

**Symptom:** Phase 1 errors out before extracting keys; console says "Calibre process detected."

**Diagnosis:** `dedrm.json` is locked by Calibre.

**Recovery:**

1. Quit Calibre via File → Quit (not just X).
2. Verify no calibre processes:

   ```powershell
   Get-Process | Where-Object { $_.Name -match "calibre" }
   ```

3. End any remaining `calibre*.exe` processes via Task Manager.
4. Re-run keyfinder.

## Keyfinder fails with "Python not found"

**Symptom:** `Run_keyfinder_admin.vbs` reports Python missing.

**Diagnosis:** Either Python isn't installed, OR only the WindowsApps stub is on PATH (which keyfinder skips).

**Recovery:**

1. Confirm Python state:

   ```bash
   where python
   python --version
   ```

2. If only WindowsApps appears, install Python from python.org (NOT the Microsoft Store version) and ensure "Add Python to PATH" is checked during install.
3. Alternatively: install via `uv` (`~/.local/bin/python.exe` is accepted by the keyfinder filter).

## Keyfinder crashes with STATUS_ACCESS_VIOLATION

**Symptom:** Console shows `0xC0000005` exit code from KFXKeyExtractor or KFXArchiver.

**Diagnosis:** Kindle for PC version not in the supported list (`code/modules/utils.py` `SUPPORTED_KINDLE_VERSIONS_ALT`). Hard-coded memory offsets in the extractor crash on unsupported builds.

**Recovery:**

1. Check Kindle.exe version. If outside `2.8.0–2.8.3` or `2.9.1`, this skill can't extract keys with bundled tools.
2. Check `update` action for newer KFXArchiver supporting the current Kindle version. If none → wait for upstream update OR downgrade Kindle for PC to a supported version.
3. As a workaround: try Mode B (KFXArchiver-only) by re-running the keyfinder with reset config:

   ```bash
   rm ~/Tools/Kindle_Key_Finder/key_finder_config.json
   # Re-run, choose Mode B in the wizard
   ```

## Sync after firewall disable left a 2.9.x installer

**Symptom:** Ran `sync`, completed, but `%LOCALAPPDATA%\Amazon\Kindle\updates\` has a fresh `KindleForPC-installer.exe`.

**Diagnosis:** Firewall-disabled window was long enough for Amazon to download an installer. ICACLS deny prevents future writes but not one that landed mid-window.

**Recovery:**

```bash
# Verify installer wasn't run yet:
powershell.exe -NoProfile -Command "(Get-Item '${LOCALAPPDATA}\Amazon\Kindle\application\Kindle.exe').VersionInfo.FileVersion"
# If still 2.8.0.70980, delete:
rm -f "${LOCALAPPDATA}/Amazon/Kindle/updates/KindleForPC-installer.exe"
```

The `sync-finalize.sh` script does this automatically. If `sync-finalize.sh` ran but the file persisted, re-run with verbose:

```bash
bash -x "${CLAUDE_PLUGIN_ROOT}/skills/kindle-dedrm/scripts/sync-finalize.sh"
```

## Books fail Phase 3 import to Calibre

**Symptom:** Phase 1 extracts keys successfully, Phase 2 writes dedrm.json, but Phase 3 reports import failures for some books.

**Diagnosis:** Possible causes:

- DeDRM plugin not loaded in Calibre
- KFX Input plugin not loaded in Calibre
- Calibre Library path mismatch
- Book file corrupted (rare)

**Recovery:**

1. Verify both plugins are loaded:

   ```bash
   ls "${APPDATA}/calibre/plugins/" | grep -iE "dedrm|kfx"
   ```

   Expect `DeDRM.zip` and `KFX Input.zip` (or similar names).

2. Verify dedrm.json has keys:

   ```bash
   cat "${APPDATA}/calibre/plugins/dedrm.json" | head -20
   ```

   Should have entries under `kindlekeys` or similar.

3. Manually try importing one book via Calibre GUI (drag-and-drop the `.azw` file). If Calibre import works manually but not via Phase 3, keyfinder's calibredb invocation has a path issue — open `~/Tools/Kindle_Key_Finder/key_finder.log` for detail.

## Cleanup leaves orphaned firewall rule

**Symptom:** After running `cleanup --full`, `Get-NetFirewallRule -DisplayName "Block Kindle for PC (lock 2.8.0)"` still returns the rule.

**Diagnosis:** Either the rule was created with a different name, OR cleanup ran without admin privileges.

**Recovery:**

```powershell
# As admin:
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*Kindle*" } | Select-Object DisplayName, Enabled
Remove-NetFirewallRule -DisplayName "Block Kindle for PC (lock 2.8.0)"
```

## Cleanup can't delete ~/Tools/Kindle_Key_Finder

**Symptom:** `rm -rf ~/Tools/Kindle_Key_Finder` reports "device or resource busy" or "permission denied."

**Diagnosis:** A process holds a file in the directory. Could be keyfinder still running, or Windows indexer / antivirus scanning.

**Recovery:**

```powershell
Get-Process | Where-Object { $_.Path -like "*Kindle_Key_Finder*" -or $_.Path -like "*KFXKey*" -or $_.Path -like "*KFXArchiver*" }
# Kill any matches, then retry rm
```

If Windows indexer is the holder, restart Explorer:

```powershell
Stop-Process -Name explorer -Force
# Explorer auto-restarts
```

## "icacls deny" cleanup leaves the deny in place

**Symptom:** After `cleanup`, `icacls "%LOCALAPPDATA%\Amazon\Kindle\updates"` still shows `(DENY)(W)` for the user.

**Diagnosis:** Cleanup script's `/remove:d` argument didn't match the trustee name format. Trustee must match exactly what `icacls` printed (e.g., `AzureAD\<user>`, not `<user>`).

**Recovery:**

```powershell
# Check exact trustee name:
icacls "$env:LOCALAPPDATA\Amazon\Kindle\updates"
# Remove with the exact name (note: full domain prefix included):
icacls "$env:LOCALAPPDATA\Amazon\Kindle\updates" /remove:d "AzureAD\<user>"
```

## After `cleanup --full`, Calibre still has plugins

**Symptom:** `cleanup --full` ran, but Calibre still shows KFX Input and DeDRM under Preferences → Plugins.

**Diagnosis:** Calibre plugins must be removed via Calibre's GUI (or by editing Calibre's plugin database directly, which is fragile). Cleanup script intentionally does NOT auto-remove plugins because Calibre may be in use for other workflows.

**Recovery (manual):**

1. Open Calibre.
2. Preferences → Plugins.
3. Expand "File type plugins". Find DeDRM.
4. Click → Remove plugin.
5. Repeat for KFX Input.
6. Restart Calibre.
7. Optionally remove `dedrm.json`:

   ```bash
   rm "${APPDATA}/calibre/plugins/dedrm.json"
   ```

## Drift check shows tutorial article hash changed but content looks the same

**Symptom:** `update` action reports the techy-notes.com article body hash changed, but on visual inspection nothing has materially changed.

**Diagnosis:** Article likely got a minor edit (typo, ad rotation, footer update) that doesn't affect the procedure. WebFetch processes the page through a slightly non-deterministic model summarization step.

**Recovery:**

1. Re-fetch with a more targeted prompt that asks ONLY for the version pins and download URL:

   ```text
   /context7 (or equivalent webfetch) — fetch URL, extract:
   - Kindle for PC version required
   - DeDRM_tools version required
   - Kindle_Key_Finder zip URL
   ```

2. If the targeted facts are unchanged, accept the drift signal as cosmetic and update the page-hash baseline in `references/sources.md`.

3. If the targeted facts changed, propagate to `references/versions.md` and re-run `setup` portions affected.
