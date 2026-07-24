---
name: setup
description: "Verify the context-guard plugin's wiring on this machine — jq, statusline tee wiring (including a stale plugin-cache path), live-session snapshot freshness — print the exact statusline edit for the operator, and optionally seed ~/.claude/context-guard/zones.json from the shipped defaults. Use when: 'set up context-guard', 'is the context tee working', 'wire the context statusline', a consumer reports zone unknown in a live session, or after a plugin update moved the cache path. Actions: check (read-only; never edits settings), apply (writes ONLY zones.json, on explicit request)."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Setup with the narrow-write carve-out: every prerequisite is either a system tool (`jq`) or an edit
to the **user's own** `settings.json`, and plugin setup must never mutate Claude Code user settings
(`docs/PLUGIN-PHILOSOPHY.md`, "Setup is explicit and repeatable"). So `check` inspects, reports
PASS/FAIL/INFO with one remediation line per FAIL, and **prints the exact statusline edit for the
operator to apply by hand**. `apply` is scoped to the ONE machine file whose schema this plugin
owns — `~/.claude/context-guard/zones.json` — and touches nothing else.

The scripts are the source of truth for their own behavior — read
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-tee.sh` and
`${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh` first; probe what they actually do rather than
reciting this file. The consumer-facing constants (snapshot path pattern, staleness rule, default
zone bands, zones.json shape) are owned by
`${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

1. **`jq`** — `command -v jq`. FAIL if absent: without it the wrapper cannot tee (it stays
   transparent and shows a visible notice), the standalone statusline degrades, and the zone
   resolver prints `unknown`. Remediation: install jq (<https://jqlang.org/download/>).
2. **Statusline wiring state** — read (never write) the user's `~/.claude/settings.json`, and note
   any project-level `statusLine` that shadows it. Distinguish FOUR states:
   - **No `statusLine` configured** — the wrapper is not running because nothing is. Print the
     standalone wiring from the template below (the wrapper is then the whole statusline).
   - **`statusLine` present, command does not reference this plugin's `statusline-tee.sh`** —
     wrapper missing. Print the wrapped wiring below with the user's current command preserved as
     the wrapped command.
   - **`statusLine` references a `context-guard` `statusline-tee.sh` at a path that differs from
     the currently resolved `${CLAUDE_PLUGIN_ROOT}`** — STALE WIRING, even when the old file still
     exists on disk: the plugin cache path changes on every plugin update and the old version's
     directory can linger, silently running yesterday's tee. Compare the wired path string against
     the resolved `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-tee.sh`; on any mismatch print the
     corrected edit with the current path. (Existence of the wired file is NOT the test.)
   - **Wired path matches the resolved plugin root** — PASS.
3. **Live-session snapshot freshness** — this session's id is `${CLAUDE_SESSION_ID}`. Probe
   `~/.claude/context-guard/context/${CLAUDE_SESSION_ID}.json`:
   - Exists and `captured_at` is within the reader contract's 10-minute staleness window → PASS
     (zone-informed consumers get real data). Also report the zone:
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh" ${CLAUDE_SESSION_ID}`.
   - Fresh but `used_percentage` or `current_usage` null → INFO: documented early-session or
     post-`/compact` statusline state; the resolver correctly answers `unknown`. Not a defect.
   - Absent or stale while step 2 reported correct wiring → FAIL: the wrapper is wired but not
     running (the statusline refreshes only in interactive sessions; also re-check step 2's
     stale-path state). Note the file only updates while this session is interactive.
   - If the literal string `${CLAUDE_SESSION_ID}` appears unexpanded above, report that this
     Claude Code version lacks the substitution and consumers will take the conservative path —
     probe the newest file in `~/.claude/context-guard/context/` instead, labeled as such.
4. **zones.json state** — read-only report: absent (shipped defaults 50/75 in effect — valid
   zero-config state, not a defect), present and valid (report the bands in effect), or present
   but malformed (report that the resolver falls back to shipped defaults with a stderr notice;
   remediation: `apply`).
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

   Shell-syntax guard: the wrapped form passes the user's command as ARGV — it only works for
   plain `executable arg…` commands. If the current command contains shell syntax (an inline env
   assignment like `THEME=dark my-statusline`, a pipe, `&&`, `;`, or quoting), print the
   shell-wrapped variant instead, preserving the original command verbatim inside it:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash \"<plugin-root>/scripts/statusline-tee.sh\" sh -c '<current statusline command>'"
     }
   }
   ```

   Windows note: the command must run under Git Bash — `bash` is invoked explicitly for exactly
   that reason (the script's stated shell requirement). Caveat to state with the printed edit: the
   plugin cache path changes on every plugin update, so re-run `check` after updating the plugin
   and re-apply the edit if the path moved (step 2 detects this even while the old path still
   exists).
6. **Dotfiles tracking proposal** — the printed edit changes a durable user-scope file the operator
   maintains. When the operator's home directory is managed by a dotfiles system (chezmoi, yadm, a
   bare-repo setup, ...), surface the reminder to capture the `settings.json` change through that
   system's own add/track flow so the wiring survives machine rebuilds. This skill only surfaces
   the reminder; it runs no dotfiles command.

## `apply` (writes ONLY zones.json, on explicit request)

Seed or refresh `~/.claude/context-guard/zones.json` from the shipped defaults
(`smart_max_used_percentage: 50`, `acceptable_max_used_percentage: 75` — the reader contract owns
these numbers; read them from `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md` rather than this
file if they ever disagree):

1. **File absent** — create the directory if needed and write exactly:

   ```json
   {
     "smart_max_used_percentage": 50,
     "acceptable_max_used_percentage": 75
   }
   ```

2. **File present** — converge, don't clobber: set the two recognized keys to the shipped defaults
   ONLY if the operator asked for a reset (otherwise leave valid existing values alone and just
   report them); **preserve every unrecognized key byte-for-byte** (the file is a shared SSOT the
   operator's own statusline may extend). Use `jq` to merge so the result stays valid JSON. If
   `jq` is absent while the file exists, FAIL with the jq install remediation
   (<https://jqlang.org/download/>) instead of attempting a merge — never risk clobbering the
   operator's keys with a jq-less rewrite. (Step 1's template write needs no jq.)
3. **Idempotent** — a second identical `apply` produces no content change; say so.
4. **Report exactly what was written** (old bands → new bands, unrecognized keys preserved), and
   remind that consumers re-read the file on their next zone decision — no restart needed.

`apply` never touches `settings.json`, the snapshot directory, or any other file. Statusline wiring
stays print-only (owner-approved execution-shape decision).

## What this skill does NOT do

- Edit `settings.json` (user or project), write `pluginConfigs`, or touch any Claude Code settings
  surface — the printed edit is the operator's to apply.
- Install `jq` or any system package.
- Write to the snapshot directory `~/.claude/context-guard/context/` — the tee owns those files.
