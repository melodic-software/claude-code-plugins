---
name: setup
description: "Verify the context-guard plugin's wiring on this machine — jq, the installed statusline shim, statusline wiring (including legacy version-pinned plugin-cache paths), live-session snapshot freshness — print the exact statusline edit for the operator, and install the shim plus seed ~/.claude/context-guard/zones.json from the shipped defaults. Use when: 'set up context-guard', 'is the context tee working', 'wire the context statusline', a consumer reports zone unknown in a live session, or after a plugin update. Actions: check (read-only; never edits settings), apply (writes ONLY inside ~/.claude/context-guard/ — the shim and zones.json — on explicit request)."
argument-hint: "check | apply [reset]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Setup with the narrow-write carve-out: every prerequisite is either a system tool (`jq`) or an edit
to the **user's own** `settings.json`, and plugin setup must never mutate Claude Code user settings
(`docs/PLUGIN-PHILOSOPHY.md`, "Setup is explicit and repeatable"). So `check` inspects, reports
PASS/FAIL/INFO with one remediation line per FAIL, and **prints the exact statusline edit for the
operator to apply by hand**. `apply` writes ONLY inside this plugin's own operator-home directory
`~/.claude/context-guard/` — the statusline shim (`bin/statusline-shim.sh`) and the zones SSOT
(`zones.json`) — and touches nothing else.

**Why the shim exists (the durable-wiring rule).** `${CLAUDE_PLUGIN_ROOT}` is version-pinned and
changes on every plugin update, and the old version directory is pruned about 14 days later
(plugins reference, "Plugin cache and file access"). A statusline wired straight to
`<plugin-root>/scripts/statusline-tee.sh` therefore stops teeing at the next version bump and, once
the old directory is pruned, `bash <missing-path>` exits 127 and takes the operator's WHOLE
statusline down with it. So the operator wires the **shim**, never the tee: the shim lives at a
path that never changes, resolves the newest installed tee at run time, and degrades to running the
wrapped command alone when no tee is installed. Read
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh` for its actual resolution rule rather than
reciting this paragraph.

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
2. **Installed shim state** — the shim is the wiring target, so check it before the wiring. Compare
   `~/.claude/context-guard/bin/statusline-shim.sh` against
   `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh` (the installed copy is byte-identical by
   contract, so `cmp -s` is the test):
   - **Absent** — FAIL when the statusline is wired to it (that wiring cannot run), INFO otherwise.
     Remediation: `apply`.
   - **Present and identical** — PASS. Nothing about it needs revisiting on a plugin update; that
     is the whole point of the shim.
   - **Present but differing** — INFO, not FAIL: the installed copy is an older (or hand-edited)
     revision that still resolves the newest tee. Report the shipped `# shim-revision:` marker
     against the installed one and offer `apply` as the refresh.
   - **The SHIPPED source is absent** (no `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh`) —
     INFO, and skip the comparison entirely: this installed plugin version predates the shim
     (< 0.2.0). Never report the operator's installed copy as drifted on this branch. Remediation:
     `/plugin update context-guard`, then re-run `check`. Until then the legacy version-pinned
     wiring in step 3 is the only wiring this version can offer.
3. **Statusline wiring state** — read (never write) every settings scope that can carry a
   `statusLine` (user `~/.claude/settings.json`, project `.claude/settings.json`, local
   `.claude/settings.local.json`) and determine which one owns the EFFECTIVE command (the most
   specific scope wins). All wiring states below are evaluated against that effective command,
   and the printed edit in step 6 targets THAT scope's file — wiring the user file while a
   project-level `statusLine` shadows it would apply cleanly and never run; when a shadow
   exists, say so explicitly and print the edit for the shadowing file (or note that removing
   the override is the alternative). Distinguish FOUR states:
   - **No `statusLine` configured** — the wrapper is not running because nothing is. Print the
     standalone wiring from the template below (the shim is then the whole statusline).
   - **`statusLine` present, command references neither the shim nor this plugin's
     `statusline-tee.sh`** — wrapper missing. Print the wrapped wiring below with the user's
     current command preserved as the wrapped command.
   - **`statusLine` references a `context-guard` `statusline-tee.sh` under the plugin cache
     (`.../plugins/cache/<marketplace>/context-guard/<version>/scripts/…`)** — LEGACY
     VERSION-PINNED WIRING, regardless of whether that file currently exists. It is running
     today only until the next version bump, and it breaks the whole statusline once the old
     version directory is pruned (~14 days after an update). Report it as the failure mode this
     plugin's shim exists to remove, and print the shim wiring as the fix (step 2's `apply` first
     if the shim is not installed). An interim `[ -f … ]` existence guard around such a path is
     the same state: it survives pruning but still stops teeing on a version bump.
   - **`statusLine` invokes `~/.claude/context-guard/bin/statusline-shim.sh`** — PASS. No path
     comparison against `${CLAUDE_PLUGIN_ROOT}` applies or is meaningful here; the shim resolves
     the tee at run time.
4. **Live-session snapshot freshness** — this session's id is `${CLAUDE_SESSION_ID}`. Probe
   `~/.claude/context-guard/context/${CLAUDE_SESSION_ID}.json`:
   - Exists and `captured_at` is within the reader contract's 10-minute staleness window → PASS
     (zone-informed consumers get real data). Also report the zone:
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh" ${CLAUDE_SESSION_ID}`.
   - Fresh but `used_percentage` or `current_usage` null → INFO: documented early-session or
     post-`/compact` statusline state; the resolver correctly answers `unknown`. Not a defect.
   - Absent or stale while step 3 reported correct wiring → FAIL: the wrapper is wired but not
     running (the statusline refreshes only in interactive sessions; also re-check steps 2 and 3 —
     a shim that is wired but not installed produces exactly this). Note the file only updates
     while this session is interactive.
   - If the literal string `${CLAUDE_SESSION_ID}` appears unexpanded above, report that this
     Claude Code version lacks the substitution and consumers will take the conservative path —
     probe the newest file in `~/.claude/context-guard/context/` instead, labeled as such.
5. **zones.json state** — read-only report: absent (shipped defaults 50/75 in effect — valid
   zero-config state, not a defect), present and valid (report the bands in effect), or present
   but malformed (report that the resolver falls back to shipped defaults with a stderr notice;
   remediation: `apply`).
6. **Print the operator edit** — always print the applicable statusline edit for the settings
   file that owns the effective command (step 3), marked clearly as the operator's to apply. The
   wiring target is the SHIM's fixed path — never `${CLAUDE_PLUGIN_ROOT}`, which is version-pinned
   and belongs in no operator file:

   Wrapping an existing statusline command (preserve the user's command verbatim as the trailing
   arguments):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh <current statusline command>"
     }
   }
   ```

   No statusline configured (standalone minimal statusline):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh"
     }
   }
   ```

   Shell-syntax guard: the wrapped form passes the user's command as ARGV — it only works for
   plain `executable arg…` commands. If the current command contains shell syntax (an inline env
   assignment like `THEME=dark my-statusline`, a pipe, `&&`, `;`, or quoting), print the
   shell-wrapped variant instead:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '<escaped original command>'"
     }
   }
   ```

   Sibling tees compose by nesting, each through its OWN shim — the tees are transparent wrappers,
   so the innermost command still owns stdout and the exit code. Print this form when
   `rate-limit-guard` is also installed:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh <current statusline command>"
     }
   }
   ```

   State the measured cost with that form: each tee adds roughly 0.6–0.9 s per statusline refresh
   on Windows/Git Bash (process-spawn bound), on top of the operator's own statusline command.
   `refreshInterval` sets how often that runs; the statusline is not on the input path, so the
   cost is display latency, not typing latency.

   `<escaped original command>` is the original command POSIX-escaped for single-quote embedding:
   replace every `'` in it with `'\''` before substituting (then JSON-escape the whole `command`
   string as usual). Show the final, fully escaped line — never hand the operator a template with
   raw quotes left to fix. Verify your printed edit round-trips: mentally unquote it back and
   confirm it reproduces the original command byte-for-byte.

   Windows note: the command must run under Git Bash — `bash` is invoked explicitly for exactly
   that reason (the script's stated shell requirement); with Git Bash absent Claude Code routes
   statusline commands through PowerShell and this wiring does not apply (statusline reference,
   "Windows configuration"). State this with the printed edit: the wiring is applied ONCE and
   survives every later plugin update, because the shim — not the version-pinned cache path — is
   what the settings file names.
7. **Dotfiles tracking proposal** — the printed edit changes a durable user-scope file the operator
   maintains. When the operator's home directory is managed by a dotfiles system (chezmoi, yadm, a
   bare-repo setup, ...), surface the reminder to capture the `settings.json` change through that
   system's own add/track flow so the wiring survives machine rebuilds. This skill only surfaces
   the reminder; it runs no dotfiles command.

## `apply` (writes ONLY inside `~/.claude/context-guard/`, on explicit request)

Two files, both in this plugin's own operator-home directory. Every `apply` mode does BOTH; the
`reset` argument affects only the zones bands.

### A. Install the statusline shim

Copy `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh` to
`~/.claude/context-guard/bin/statusline-shim.sh`, creating `bin/` if needed, and `chmod +x` the
result (a no-op on Windows ACL volumes; the wiring invokes it through `bash` anyway):

- The installed copy is **byte-identical** to the shipped source — never a rewrite, never a
  templated variant. That is what makes `check` step 2 a plain `cmp`.
- **Idempotent**: if the file already exists and compares equal, write nothing and say so.
  Otherwise overwrite it (this is the update path after a plugin version bump changes the shim)
  and report the `# shim-revision:` values, old → new.
- The shim is **inert until wired**: installing it starts nothing. Only the operator's
  `settings.json` edit — step 6 of `check`, which this skill never applies — puts it on the
  statusline path. Say that explicitly when reporting the write.
- After installing, print the wiring edit (`check` step 6) so the operator's next action is in
  front of them, and note that a statusline already wired to the shim needs NO change now or on
  any future plugin update.

### B. Seed or refresh the zones SSOT

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

2. **File present** — behavior is mode-explicit, never ambiguous:
   - `apply` (no argument): REPAIR-ONLY. Valid recognized band values are left untouched and
     reported; recognized keys that are missing or invalid (non-numeric, inverted, out of range)
     are set to the shipped defaults. An operator's custom-but-valid thresholds are never
     overwritten by a bare `apply`.
   - `apply reset`: set BOTH recognized band keys to the shipped defaults explicitly.
   - Both modes **preserve every unrecognized key semantically** — same keys, same JSON values —
     (the file is a shared SSOT the operator's own statusline may extend). Preservation is
     value-level, not lexical: a `jq` merge reserializes the document, so formatting and escape
     spellings may normalize (`"blue"` → `"blue"`); consumers of this file must parse it as
     JSON, never depend on its raw bytes. Use `jq` to merge so the result stays valid JSON. If
     `jq` is absent while the file exists, FAIL with the jq install remediation
     (<https://jqlang.org/download/>) instead of attempting a merge — never risk clobbering the
     operator's keys with a jq-less rewrite. (Step 1's template write needs no jq.)
3. **Idempotent** — a second identical `apply` produces no content change; say so.
4. **Report exactly what was written** (old bands → new bands, unrecognized keys preserved), and
   remind that consumers re-read the file on their next zone decision — no restart needed.

`apply` never touches `settings.json`, the snapshot directory, or anything outside
`~/.claude/context-guard/`. Statusline wiring stays print-only (owner-approved execution-shape
decision).

## Uninstalling

Uninstalling the plugin removes the cache directory, not the operator's files. Nothing breaks: the
shim finds no tee and passes the wrapped statusline through unchanged (a wired-standalone shim
prints one notice line instead). Removing `~/.claude/context-guard/` and unwrapping the
`statusLine` command are the operator's two cleanup steps, in either order — report them together
when asked how to back this out.

## What this skill does NOT do

- Edit `settings.json` (user or project), write `pluginConfigs`, or touch any Claude Code settings
  surface — the printed edit is the operator's to apply.
- Install `jq` or any system package.
- Write to the snapshot directory `~/.claude/context-guard/context/` — the tee owns those files.
- Write anywhere outside `~/.claude/context-guard/` — including the sibling `rate-limit-guard`
  directory, whose own setup skill installs that plugin's shim.
