---
name: setup
description: "Verify the rate-limit-guard plugin's wiring on this machine — jq, statusline tee freshness, and the StopFailure hook — and print the exact statusline edit for the operator to apply. Use when: 'set up rate-limit-guard', 'is the rate-limit tee working', 'wire the rate-limit statusline', the tee file is stale, or a consuming loop lane reports guard mode unknown. Action: check (read-only; this skill never edits settings)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Check-only setup, because this plugin owns **no writable artifact** for an `apply` to converge. Its
entire configuration surface is three kinds of thing setup cannot conformingly write:

- **A system tool** (`jq`) — `check` probes it; installing it is the operator's.
- **One native `userConfig` toggle** (`rate_limit_guard_enabled`), whose only stored home is the
  `pluginConfigs` setup must never write. Reconfiguration routes through Claude Code's native flow:
  `/plugin configure rate-limit-guard` interactively, any time. Headless, `claude plugin install
  ... --config rate_limit_guard_enabled=false` seeds the value on a *fresh install only* and is
  ignored once installed, so a headless reconfigure is `claude plugin uninstall rate-limit-guard -s
  <scope> -y` then `claude plugin install rate-limit-guard@<marketplace> -s <scope> --config
  rate_limit_guard_enabled=<value>`. Both commands default to `-s user`, so pass the scope the
  plugin is *actually* installed at — `claude plugin list` reports it per plugin — and run from that
  project's directory when the scope is `project` or `local`; defaulting removes a separate user
  record while the effective install stays in place. The `-y` is what the CLI requires of an
  uninstall whose stdin or stdout is not a TTY, and is warranted only because the caller explicitly
  asked to reconfigure.
- **The statusline wiring**, which lives in the **user's own** `settings.json` — neither
  `userConfig` nor tracked project config, and a Claude Code settings surface setup must never
  mutate.

The machine files under `~/.claude/rate-limit-guard/` are not a fourth, writable surface: the tee
and the hook own them at runtime, so they are this plugin's data, not operator-editable
configuration.

So there is no `apply`: `check` inspects, reports PASS/FAIL/INFO with one remediation line per
FAIL, and **prints the exact statusline edit for the operator to apply by hand** — fully resolved,
marked as the operator's, and naming what re-invalidates it. Silence would not be the conforming
response on an unwritable surface; a printed edit is.

The scripts are the source of truth for their own behavior — read
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-tee.sh` and
`${CLAUDE_PLUGIN_ROOT}/hooks/record-rate-limit-stop.sh` first; probe what they actually do rather
than reciting this file. The consumer-facing constants (tee path, threshold, staleness rule) are
owned by `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

1. **`jq`** — `command -v jq`. FAIL if absent: without it the wrapper cannot tee (it stays
   transparent and shows a visible notice) and the standalone statusline degrades. Remediation:
   install jq (<https://jqlang.org/download/>).
2. **Statusline wiring state** — read (never write) the user's `~/.claude/settings.json`, and note
   any project-level `statusLine` that shadows it. Distinguish three states:
   - **No `statusLine` configured** — the wrapper is not running because nothing is. Print the
     standalone wiring from the template below (the wrapper is then the whole statusline).
   - **`statusLine` present, command does not reference `statusline-tee.sh`** — wrapper missing.
     Print the wrapped wiring below with the user's current command preserved as the wrapped
     command.
   - **`statusLine` references `statusline-tee.sh` but the referenced file does not exist** — stale
     path: `${CLAUDE_PLUGIN_ROOT}` changes on every plugin update (plugins reference, verified at
     authoring). Print the corrected edit with the currently resolved path.
3. **Tee freshness** — probe the fixed contract path `~/.claude/rate-limit-guard/rate-limits.json`:
   - `jq -e '.rate_limits and .captured_at'` passes and `captured_at` is within the reader
     contract's 10-minute staleness window → PASS (proactive mode available).
   - File fresh but `rate_limits` absent → INFO: this session's auth exposes no subscription
     windows (API-key or enterprise auth); consumers correctly run reactive-only. Not a defect.
   - File absent or stale while the wiring in step 2 looked correct → FAIL: the wrapper is wired
     but not running (statusline refreshes only in interactive sessions; also re-check step 2's
     stale-path state). Note the file only updates while some interactive session is active.
4. **StopFailure hook** — INFO: the hook needs no wiring (it registers via the plugin's
   `hooks/hooks.json`); confirm the plugin is enabled (`/plugin` → Installed) and report the
   effective kill switch `${user_config.rate_limit_guard_enabled}` (unexpanded or empty means the
   default `true`). Report whether `~/.claude/rate-limit-guard/stop-events.jsonl` exists — absent
   just means no rate-limit stop has been recorded yet.
5. **Print the operator edit** — always print the applicable `settings.json` statusline edit,
   marked clearly as the operator's to apply, with `<plugin-root>` replaced by the resolved
   absolute `${CLAUDE_PLUGIN_ROOT}` path:

   Wrapping an existing statusline command (preserve the user's command verbatim as the trailing
   arguments):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash \"<plugin-root>/scripts/statusline-tee.sh\" <current statusline command>"
     }
   }
   ```

   No statusline configured (standalone minimal statusline):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash \"<plugin-root>/scripts/statusline-tee.sh\""
     }
   }
   ```

   Windows note: the command must run under Git Bash — `bash` is invoked explicitly for exactly
   that reason (the script's stated shell requirement). Caveat to state with the printed edit: the
   plugin cache path changes on every plugin update, so re-run `check` after updating the plugin
   and re-apply the edit if the path moved.
6. **Dotfiles tracking proposal** — the printed edit changes a durable user-scope file the operator
   maintains. When the operator's home directory is managed by a dotfiles system (chezmoi, yadm, a
   bare-repo setup, ...), surface the reminder to capture the `settings.json` change through that
   system's own add/track flow so the wiring survives machine rebuilds. This skill only surfaces
   the reminder; it runs no dotfiles command.

## What this skill does NOT do

- Edit `settings.json` (user or project), write `pluginConfigs`, or touch any Claude Code settings
  surface — the printed edit is the operator's to apply.
- Install `jq` or any system package.
- Write to the contract directory — the wrapper and the hook own their files.
