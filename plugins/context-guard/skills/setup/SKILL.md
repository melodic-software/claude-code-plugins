---
name: setup
description: "Verify the context-guard plugin's wiring on this machine — jq, the installed statusline shim, statusline wiring (including legacy version-pinned plugin-cache paths), live-session snapshot freshness — print the exact statusline edit for the operator, and install the shim plus seed ~/.claude/context-guard/zones.json from the shipped defaults. Use when: 'set up context-guard', 'is the context tee working', 'wire the context statusline', a consumer reports zone unknown in a live session, or after a plugin update. Actions: check (read-only; never edits settings), apply (writes ONLY inside ~/.claude/context-guard/ — the shim and zones.json — on explicit request)."
argument-hint: "check | apply [defaults]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Narrow-write setup, because this plugin's surface splits in two. The statusline wiring lives in the
**user's own** `settings.json` and the `jq` prerequisite is a system tool: neither is something
plugin setup may write, so `check` inspects, reports PASS/FAIL/INFO with one remediation line per
FAIL, and **prints the exact statusline edit for the operator to apply by hand**. But this plugin
also owns its operator-home directory `~/.claude/context-guard/` — the machine file `zones.json`,
whose schema it defines and whose values the operator may edit, and the statusline shim
`bin/statusline-shim.sh`, the durable path the operator's wiring names — and those owned writable
artifacts are what oblige an `apply`. `apply` is scoped to that directory and touches nothing else.

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
   and the printed edit in step 7 targets THAT scope's file — wiring the user file while a
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
5. **zones.json state** — read-only report: absent (shipped defaults in effect — percentage 50/75
   plus the window-class token bands; valid zero-config state, not a defect), present and valid
   (report the bands in effect, both shapes), or present with a malformed shape (report per shape
   — the resolver validates percentage keys and `token_bands` independently and falls back per
   shape with a stderr notice; a v1 file without `token_bands` is valid, with shipped token bands
   silently in effect; remediation: `apply`). Note the hooks resolve zones through this same data —
   a machine with no snapshots gets silent hooks, not errors.
6. **Hook registration vs hook activation** — THREE separate facts, never collapsed into one
   status. A registered hook set that every hook exits out of immediately is the exact state an
   operator is diagnosing when injections or gating are missing, and reporting "active" because the
   plugin is enabled tells them the opposite of the runtime state.
   - **Registered** — the plugin is enabled, so `hooks/hooks.json` is loaded and the matchers fire.
     This follows from the plugin being enabled and says nothing about what the hooks then do.
   - **Hook set armed** — the `context_guard_hooks_enabled` kill switch. Read its CONFIGURED value,
     not the plugin's enablement: the value substituted here is
     `${user_config.context_guard_hooks_enabled}`. Interpret it as
     - `false` → **INERT**: registered but every hook (injection, gate, PostCompact marker) exits
       immediately without acting. Remediation: re-enable the option via `/plugin`.
     - `true` → armed.
     - anything else, including the literal `${user_config.context_guard_hooks_enabled}` surviving
       unexpanded (unset key, or a Claude Code without the substitution) → **UNKNOWN**, never
       "armed". Say which source was read and that an unset key falls back to the hooks' in-script
       default (armed); the operator-inspectable source of truth is this plugin's
       `pluginConfigs` options block in the user `settings.json`
       (`docs/conventions/hook-config-delivery` owns why the declared `default` field is not
       delivered to hook processes).
   - **Gate posture** — `zone_hook_mode` is `${user_config.zone_hook_mode}`, read and interpreted
     the same way. Only `blocking` makes the PreToolUse gate do anything; `advisory` (the in-script
     default) leaves it inert while the injection hook still runs. Report it separately: an armed
     hook set with an advisory posture is a different runtime state from an inert hook set, and
     only one of the two is a defect.
7. **Print the operator edit** — always print the applicable statusline edit for the settings
   file that owns the effective command (step 3), marked clearly as the operator's to apply. The
   wiring target is the SHIM's fixed path — never `${CLAUDE_PLUGIN_ROOT}`, which is version-pinned
   and belongs in no operator file:

   **Unwrap before you compose.** `<current statusline command>` below means the operator's OWN
   renderer, never the raw effective `command` string. Before substituting, strip every leading
   guard-shim invocation from that string — `bash <path>/context-guard/bin/statusline-shim.sh` and
   `bash <path>/rate-limit-guard/bin/statusline-shim.sh`, in whatever order they appear — plus any
   legacy `bash <plugin-cache>/…/statusline-tee.sh` prefix, and treat what remains as the renderer.
   Substituting the raw string instead is what produces `context → rate → rate → renderer` when the
   sibling plugin was configured first, or a doubled self-wrap on a re-run: each duplicated tee runs
   and writes on EVERY refresh and costs another 0.6–0.9 s (below). Unwrapping also makes the
   printed edit idempotent — re-running `check` on already-correct wiring prints the wiring it
   already has.

   Wrapping an existing statusline command (preserve the user's unwrapped command verbatim as the
   trailing arguments):

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

   `<escaped original command>` is the original command POSIX-escaped for single-quote embedding:
   replace every `'` in it with `'\''` before substituting (then JSON-escape the whole `command`
   string as usual). Show the final, fully escaped line — never hand the operator a template with
   raw quotes left to fix. Verify your printed edit round-trips: mentally unquote it back and
   confirm it reproduces the original command byte-for-byte.

   Sibling tees compose by nesting, each through its OWN shim — the tees are transparent wrappers,
   so the innermost command still owns stdout and the exit code. Print this form only when
   `rate-limit-guard` is installed AND its shim is already present at
   `~/.claude/rate-limit-guard/bin/statusline-shim.sh`. The sibling shim is written by
   `/rate-limit-guard:setup apply`, which the operator may not have run yet — naming a path that
   does not exist reintroduces exactly the failure this wiring exists to remove, because `bash
   <missing-path>` exits 127 before the operator's renderer ever runs. When the sibling plugin is
   installed but its shim is absent, print the single-shim form above and say that
   `/rate-limit-guard:setup apply` followed by a re-run of this check yields the combined wiring:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh <current statusline command>"
     }
   }
   ```

   The shell-syntax guard applies UNCHANGED to this form: `<current statusline command>` is the
   innermost ARGV here too, so a command carrying shell syntax must be substituted as
   `sh -c '<escaped original command>'` — never raw. Substituting `THEME=dark my-statusline` raw
   makes `THEME=dark` the executable, which fails `command not found` (127) instead of setting the
   variable. The shim paths are the only part that nests; the innermost substitution rule never
   changes:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh sh -c '<escaped original command>'"
     }
   }
   ```

   State the measured cost with the combined form: each tee adds roughly 0.6–0.9 s per statusline
   refresh on Windows/Git Bash (process-spawn bound), on top of the operator's own statusline
   command. `refreshInterval` sets how often that runs; the statusline is not on the input path, so
   the cost is display latency, not typing latency.

   Windows note: the command must run under Git Bash — `bash` is invoked explicitly for exactly
   that reason (the script's stated shell requirement); with Git Bash absent Claude Code routes
   statusline commands through PowerShell and this wiring does not apply (statusline reference,
   "Windows configuration"). State this with the printed edit: the wiring is applied ONCE and
   survives every later plugin update, because the shim — not the version-pinned cache path — is
   what the settings file names.
8. **Dotfiles tracking proposal** — the printed edit changes a durable user-scope file the operator
   maintains. When the operator's home directory is managed by a dotfiles system (chezmoi, yadm, a
   bare-repo setup, ...), surface the reminder to capture the `settings.json` change through that
   system's own add/track flow so the wiring survives machine rebuilds. This skill only surfaces
   the reminder; it runs no dotfiles command.

## `apply` (writes ONLY inside `~/.claude/context-guard/`, on explicit request)

Two files, both in this plugin's own operator-home directory. Every `apply` mode does BOTH; the
`defaults` argument affects only the zones bands.

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
  `settings.json` edit — step 7 of `check`, which this skill never applies — puts it on the
  statusline path. Say that explicitly when reporting the write.
- After installing, print the wiring edit (`check` step 7) so the operator's next action is in
  front of them, and note that a statusline already wired to the shim needs NO change now or on
  any future plugin update.

### B. Seed or refresh the zones SSOT

Seed or refresh `~/.claude/context-guard/zones.json` from the shipped defaults
(`smart_max_used_percentage: 50`, `acceptable_max_used_percentage: 75`, and the window-class
`token_bands` — the reader contract owns these numbers; read them from
`${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md` rather than this file if they ever disagree):

1. **File absent** — create the directory if needed and write exactly:

   ```json
   {
     "smart_max_used_percentage": 50,
     "acceptable_max_used_percentage": 75,
     "token_bands": {
       "200000": { "smart_max_tokens": 100000, "acceptable_max_tokens": 160000 },
       "1000000": { "smart_max_tokens": 200000, "acceptable_max_tokens": 400000 }
     }
   }
   ```

2. **File present** — behavior is mode-explicit, never ambiguous:
   - `apply` (no argument): REPAIR-ONLY. Valid recognized band values are left untouched and
     reported; recognized keys that are missing or invalid (non-numeric, inverted, out of range —
     for `token_bands`, invalid per the reader contract's per-shape validity rules) are set to the
     shipped defaults. A v1 file's ABSENT `token_bands` is repaired by adding the shipped token
     bands (absence is valid zero-config for the resolver, but the seeded SSOT should carry the
     full tunable surface). An operator's custom-but-valid thresholds are never overwritten by a
     bare `apply`.
   - `apply defaults`: set ALL recognized band keys (both percentage keys and `token_bands`) to
     the shipped defaults explicitly. This converges forward to a known state; it is not teardown,
     and it never removes the file or any key it does not recognize.
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
prints one notice line instead). Two operator cleanup steps remain, and their ORDER matters —
report both together, in this order, when asked how to back this out:

1. **Unwrap the `statusLine` command first**, restoring the operator's own renderer (or removing
   the field entirely if the shim was the whole statusline).
2. **Then remove `~/.claude/context-guard/`.**

Deleting the directory while the wiring still names the shim leaves `settings.json` invoking a
missing file: `bash <missing-path>` exits 127 and takes the WHOLE statusline down — the exact
failure the shim exists to prevent. The shim's own no-tee fallback cannot cover this, because the
fallback lives in the file that was just deleted.

## What this skill does NOT do

- Edit `settings.json` (user or project), write `pluginConfigs`, or touch any Claude Code settings
  surface — the printed edit is the operator's to apply.
- Install `jq` or any system package.
- Write to the snapshot directory `~/.claude/context-guard/context/` — the tee owns those files.
- Write anywhere outside `~/.claude/context-guard/` — including the sibling `rate-limit-guard`
  directory, whose own setup skill installs that plugin's shim.
