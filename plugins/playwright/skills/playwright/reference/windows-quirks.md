# Windows / Git Bash quirks

Our content — not from upstream. Captures empirically-verified behavior on Windows 11 + Git Bash + locally-installed Chrome.

## `--headed` browser opens but doesn't auto-focus

**Symptom:** pass `--headed` to `open`, browser spawns, but you don't see a window.

**Actual behavior:** browser IS open with a valid `MainWindowHandle`, but Windows' foreground-activation policy ("no-steal focus" rule) keeps it behind other windows because the spawning process (Claude Code → Git Bash → `playwright-cli` daemon → Chrome) isn't the foreground process.

**Diagnosis:**

```powershell
Get-Process chrome | Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object Id, MainWindowTitle
# Look for the browser's title — alt-tab to find it
```

**Workarounds, in order:**

1. **Alt-tab** — the window is there, just not focused
2. **Force foreground via dedicated PowerShell helper** after opening:

   ```bash
   playwright-cli -s=demo open https://example.com --headed
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/playwright/scripts/force-chrome-foreground.ps1" -TitleMatch 'Example'
   ```

   Helper (`scripts/force-chrome-foreground.ps1`) wraps the Win32 `SetForegroundWindow` / `ShowWindow` P/Invoke and no-ops on non-Windows. Pass `-TitleMatch <regex>` to disambiguate when multiple Chrome windows are open.

3. **`playwright-cli show`** — opens Microsoft's visual dashboard that auto-focuses and lets you inspect all running sessions with live screencasts

4. **Accept headless as default** — for autonomous E2E (the primary use case), you don't need to watch. Screenshots and snapshots give you everything

## `playwright-cli install` resets shell CWD on Windows

**Symptom:** after running `playwright-cli install`, subsequent commands behave as if CWD changed.

**Actual behavior:** `install` emits `Shell cwd was reset to <path>` on Windows/Git Bash. Cosmetic in the tool's view — Bash tool's CWD state is unaffected and subsequent commands work normally. But `install` step does NOT leave you inside the `.playwright/` workspace dir it created.

**Rule:** run `install` once when prompted, then operate from your repo's CWD. Subsequent `playwright-cli` commands respect current shell CWD.

## Artifacts land relative to CWD at command time

`snapshot`, `screenshot`, `console`, `network`, `pdf`, and video recordings write to `.playwright-cli/` **relative to shell CWD when each command runs**, NOT the workspace init dir.

**Practical impact in a worktree:**

```bash
cd /path/to/my-feature-worktree
playwright-cli -s=test open https://example.com       # writes to <worktree>/.playwright-cli/
cd /tmp
playwright-cli -s=test snapshot                        # writes to /tmp/.playwright-cli/  ← surprise
```

Stick to one CWD per session, or pass absolute paths:

```bash
playwright-cli -s=test screenshot --filename=/absolute/path/out.png
```

Add `.playwright-cli/` to the project's `.gitignore` so artifacts never land in version control.

## Google and other anti-bot sites may captcha

Chromium under Playwright control has a fingerprint that Google, Cloudflare, and similar services detect. Search results may redirect to `/sorry/index` or a CAPTCHA page. Not a CLI bug — anti-automation countermeasure.

**Workarounds:**

- For E2E against your own app: use localhost endpoints (no fingerprinting)
- For smoke-tests: use `example.com` or similar
- For search flows: DuckDuckGo is more bot-friendly than Google

## Unix socket daemon works on Windows (despite third-party speculation)

Some third-party blog posts warn that CLI's Unix-socket daemon architecture may fail on Windows. **Empirically verified 2026-04-24 on v0.1.8:** works fine under MSYS2 socket emulation. No intervention needed.

**If you do hit socket errors:** `playwright-cli kill-all` to reap zombie daemons, then retry.

## Cloud session limitation (inherited from infrastructure)

In Claude Code cloud sessions (Ubuntu 24.04 sandbox), `playwright-cli install-browser` fails — the sandbox blocks browser downloads to `storage.googleapis.com/chrome-for-testing-public`. Local sessions on Windows/macOS/Linux are unaffected because they auto-detect system Chrome.
