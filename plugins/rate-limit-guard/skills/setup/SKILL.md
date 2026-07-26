---
name: setup
description: "Verify the rate-limit-guard plugin's wiring on this machine — jq, the installed statusline shim, statusline wiring (including legacy version-pinned plugin-cache paths), tee freshness, and the StopFailure hook — print the exact statusline edit for the operator to apply, and install the statusline shim. Use when: 'set up rate-limit-guard', 'is the rate-limit tee working', 'wire the rate-limit statusline', the tee file is stale, or a consuming loop lane reports guard mode unknown. Actions: check (read-only; never edits settings), apply (writes ONLY ~/.claude/rate-limit-guard/bin/statusline-shim.sh, on explicit request)."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Narrow-write setup. This plugin's **configuration** surface is three kinds of thing setup cannot
conformingly write:

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

So `check` inspects, reports PASS/FAIL/INFO with one remediation line per FAIL, and **prints the
exact statusline edit for the operator to apply by hand** — fully resolved, marked as the
operator's, and naming what re-invalidates it. Silence would not be the conforming response on an
unwritable surface; a printed edit is.

What obliges an `apply` is not configuration at all. The tee's and the hook's machine files under
`~/.claude/rate-limit-guard/` remain runtime-owned plugin data, not an operator-editable surface —
but the **statusline shim** `~/.claude/rate-limit-guard/bin/statusline-shim.sh` is an owned
writable artifact this plugin must place, because it is the durable path the operator's own wiring
names. `apply` writes that one file and nothing else.

**Why the shim exists (the durable-wiring rule).** `${CLAUDE_PLUGIN_ROOT}` is version-pinned and
changes on every plugin update, and the old version directory is pruned about 14 days later
(plugins reference, "Plugin cache and file access"). A statusline wired straight to
`<plugin-root>/scripts/statusline-tee.sh` therefore stops teeing at the next version bump and, once
the old directory is pruned, `bash <missing-path>` exits 127 and takes the operator's WHOLE
statusline down with it. So the operator wires the **shim**, never the tee: the shim lives at a
path that never changes, resolves the newest installed tee at run time, and degrades to running the
wrapped command alone when no tee is installed.

The scripts are the source of truth for their own behavior — read
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh`,
`${CLAUDE_PLUGIN_ROOT}/scripts/statusline-tee.sh` and
`${CLAUDE_PLUGIN_ROOT}/hooks/record-rate-limit-stop.sh` first; probe what they actually do rather
than reciting this file. The consumer-facing constants (tee path, threshold, staleness rule) are
owned by `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

1. **`jq`** — `command -v jq`. FAIL if absent: without it the wrapper cannot tee (it stays
   transparent and shows a visible notice) and the standalone statusline degrades. Remediation:
   install jq (<https://jqlang.org/download/>).
2. **Installed shim state** — the shim is the wiring target, so check it before the wiring. Compare
   `~/.claude/rate-limit-guard/bin/statusline-shim.sh` against
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
     `/plugin update rate-limit-guard`, then re-run `check`. Until then the legacy version-pinned
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
   - **`statusLine` present, command references neither the shim nor `statusline-tee.sh`** —
     wrapper missing. Print the wrapped wiring below with the user's current command preserved as
     the wrapped command.
   - **`statusLine` references a `rate-limit-guard` `statusline-tee.sh` under the plugin cache** —
     LEGACY VERSION-PINNED WIRING, regardless of whether that file currently exists. It is running
     today only until the next version bump, and it breaks the whole statusline once the old
     version directory is pruned (~14 days after an update). Report it as the failure mode the shim
     exists to remove, and print the shim wiring as the fix (`apply` first if the shim is not
     installed). An interim `[ -f … ]` existence guard around such a path is the same state: it
     survives pruning but still stops teeing on a version bump.
   - **`statusLine` invokes `~/.claude/rate-limit-guard/bin/statusline-shim.sh`** — PASS. No path
     comparison against `${CLAUDE_PLUGIN_ROOT}` applies or is meaningful here; the shim resolves
     the tee at run time.
4. **Tee freshness** — probe the fixed contract path `~/.claude/rate-limit-guard/rate-limits.json`:
   - `jq -e '.rate_limits and .captured_at'` passes and `captured_at` is within the reader
     contract's 10-minute staleness window → PASS (proactive mode available).
   - File fresh but `rate_limits` absent → INFO: this session's auth exposes no subscription
     windows (API-key or enterprise auth); consumers correctly run reactive-only. Not a defect.
   - File absent or stale while the wiring in step 3 looked correct → FAIL: the wrapper is wired
     but not running (statusline refreshes only in interactive sessions; also re-check steps 2 and
     3 — a shim that is wired but not installed produces exactly this). Note the file only updates
     while some interactive session is active.
5. **StopFailure hook** — INFO: the hook needs no wiring (it registers via the plugin's
   `hooks/hooks.json`); confirm the plugin is enabled (`/plugin` → Installed) and report the
   effective kill switch `${user_config.rate_limit_guard_enabled}` (unexpanded or empty means the
   default `true`). Report whether `~/.claude/rate-limit-guard/stop-events.jsonl` exists — absent
   just means no rate-limit stop has been recorded yet.
6. **Print the operator edit** — always print the applicable `settings.json` statusline edit,
   marked clearly as the operator's to apply. The wiring target is the SHIM's fixed path — never
   `${CLAUDE_PLUGIN_ROOT}`, which is version-pinned and belongs in no operator file:

   **Unwrap before you compose.** `<current statusline command>` below means the operator's OWN
   renderer, never the raw effective `command` string. Before substituting, strip every leading
   guard-shim invocation from that string — `bash <path>/rate-limit-guard/bin/statusline-shim.sh`
   and `bash <path>/context-guard/bin/statusline-shim.sh`, in whatever order they appear — plus any
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
       "command": "bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh <current statusline command>"
     }
   }
   ```

   No statusline configured (standalone minimal statusline):

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh"
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
       "command": "bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh sh -c '<escaped original command>'"
     }
   }
   ```

   `<escaped original command>` is the original command POSIX-escaped for single-quote embedding:
   replace every `'` in it with `'\''` before substituting (then JSON-escape the whole `command`
   string as usual). Show the final, fully escaped line — never hand the operator a template with
   raw quotes left to fix. Verify your printed edit round-trips: mentally unquote it back and
   confirm it reproduces the original command byte-for-byte.

   Sibling tees compose by nesting, each through its OWN shim — the tees are transparent wrappers,
   so the innermost command still owns stdout and the exit code. Print this form (its tee outermost,
   matching that plugin's setup skill) only when `context-guard` is installed AND its shim is
   already present at `~/.claude/context-guard/bin/statusline-shim.sh`. The sibling shim is written
   by `/context-guard:setup apply`, which the operator may not have run yet — naming a path that
   does not exist reintroduces exactly the failure this wiring exists to remove, because `bash
   <missing-path>` exits 127 before the operator's renderer ever runs. When the sibling plugin is
   installed but its shim is absent, print the single-shim form above and say that
   `/context-guard:setup apply` followed by a re-run of this check yields the combined wiring:

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
   command.
   `refreshInterval` sets how often that runs; the statusline is not on the input path, so the
   cost is display latency, not typing latency.

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

## `apply` (writes ONLY the shim, on explicit request)

Copy `${CLAUDE_PLUGIN_ROOT}/scripts/statusline-shim.sh` to
`~/.claude/rate-limit-guard/bin/statusline-shim.sh`, creating `bin/` if needed, and `chmod +x` the
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

`apply` never touches `settings.json`, `rate-limits.json`, `stop-events.jsonl`, or anything outside
`~/.claude/rate-limit-guard/bin/`.

## Uninstalling

Uninstalling the plugin removes the cache directory, not the operator's files. Nothing breaks: the
shim finds no tee and passes the wrapped statusline through unchanged (a wired-standalone shim
prints one notice line instead). Two operator cleanup steps remain, and their ORDER matters —
report both together, in this order, when asked how to back this out:

1. **Unwrap the `statusLine` command first**, restoring the operator's own renderer (or removing
   the field entirely if the shim was the whole statusline).
2. **Then remove `~/.claude/rate-limit-guard/`.**

Deleting the directory while the wiring still names the shim leaves `settings.json` invoking a
missing file: `bash <missing-path>` exits 127 and takes the WHOLE statusline down — the exact
failure the shim exists to prevent. The shim's own no-tee fallback cannot cover this, because the
fallback lives in the file that was just deleted.

## What this skill does NOT do

- Edit `settings.json` (user or project), write `pluginConfigs`, or touch any Claude Code settings
  surface — the printed edit is the operator's to apply.
- Install `jq` or any system package.
- Write to the contract files — the wrapper and the hook own `rate-limits.json` and
  `stop-events.jsonl`; `apply` owns only `bin/statusline-shim.sh`.
- Write anywhere outside `~/.claude/rate-limit-guard/` — including the sibling `context-guard`
  directory, whose own setup skill installs that plugin's shim.
