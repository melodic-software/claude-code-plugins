---
description: "Verify the rate-limits plugin on this machine: node, whether its mod runs in this session, the snapshot file's freshness, the StopFailure hook, every option's effective value, and a directory left by the plugin's earlier name. Use when: 'set up rate-limits', 'is rate-limits working', the snapshot file is stale, a consuming loop lane reports guard mode unknown, or after a plugin update. Actions: check (read-only, default; prints every remediation and never edits settings, scripts or files), apply (on explicit request, migrates only the directory left by the earlier plugin name: merges its stop record into ~/.claude/rate-limits/stop-events.jsonl, old records first, and removes the directory)."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v node*)"
shell: bash
---

## Pre-computed context

`check`'s `node` probe ran at load time. Read this row instead of re-issuing it; it shows the
tool's path when present, or `absent` when missing:

- `node`: !`command -v node 2>/dev/null || echo absent`

- Leftover directory from the plugin's earlier name (its entries, or `(absent)`): !`if [ -d "$HOME/.claude/rate-limit-guard" ]; then ls -A "$HOME/.claude/rate-limit-guard" 2>&1; else echo "(absent)"; fi`

A row reading `[shell command execution disabled by policy]` carries no result: run that
row's probe via Bash instead.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

## Purpose

Narrow-write setup (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
marketplace repository): `check` inspects and reports PASS/FAIL/INFO with one remediation line per
FAIL. The plugin owns its machine-scope runtime directory, `~/.claude/rate-limits/`; `apply` writes
there only to finish the migration of the directory the plugin kept under its earlier name, and
writes nothing else. Every other surface is unwritable and handled the check-only way:

- **Native `userConfig`**: eight options whose only stored home is the `pluginConfigs` setup must
  never write. Reconfigure through Claude Code's native flow, interactively with
  `/plugin configure rate-limits@<marketplace>` or by a headless route, as the marketplace's
  plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Apply the scope and failure-signal caveats in its
  [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
  Read both sections and print what they give, the fallback route, its behavior on an
  already-installed plugin and the scope to pass included, rather than only naming them, and
  leave out the verified-version record.
  Never uninstall to reconfigure; that section links what an uninstall deletes. Afterwards rerun
  `check` in a **fresh session**, since a same-session `check` can still show the old value, and
  report the observed effective value, never an unobserved change.
  - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
    when a saved value applies, fetch
    [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
    live.
- **External prerequisites**: `node` and the Claude Code version, which `check` probes and whose
  install is the person's.

The files under `~/.claude/rate-limits/` are runtime-owned plugin data, written by the module
and the StopFailure hook, not an operator-editable surface.

Action routing: no argument or `check` runs the check; `apply` runs the earlier-name migration
below.

The code is the source of truth for its own behavior. Each `check` step below states what its row
needs; read `${CLAUDE_PLUGIN_ROOT}/hooks/register.tsx` or
`${CLAUDE_PLUGIN_ROOT}/hooks/record-rate-limit-stop.sh` only for a finding no step covers. The consumer-facing constants (snapshot path, threshold, staleness rule)
are owned by `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

Label every row PASS, FAIL, INFO or UNKNOWN. A check that cannot run here (a command missing or
refused, a file the session may not read) is UNKNOWN with the reason, never "skipped" or "not run".
Give each FAIL exactly one remediation line; a FAIL that depends on a condition names it in that
line.

1. **`node`.** The pre-computed `node` row. FAIL if absent: the `StopFailure` row in
   `hooks/hooks.json` is exec form, `"command": "node"` with `hooks/exec-bash.mjs` in `args`, so
   without `node` on `PATH` the hook never launches, a launch failure is non-blocking, and no
   rate-limit stop is recorded; and the module writes the snapshot by running
   `node lib/write-snapshot.mjs`, so no snapshot is written either. The module's lines, band row
   and status tool do not need it. Remediation: install Node.js (<https://nodejs.org/en/download>)
   yourself and restart Claude Code.
   - **Pointer**: when whether a Claude Code install supplies `node` is in doubt, fetch
     [setup § Install with npm](https://code.claude.com/docs/en/setup#install-with-npm) live.
2. **Module state.** The plugin's module (`hooks/register.tsx`) writes the snapshot file and sends
   the rate-limit lines; it loads only where mods can. Decide this session's state from inside this
   session, never from a separate process: a `claude` you launch through Bash reads neither this
   session's flags nor its `--settings` overlay.
   - Run `claude --version`. Older than 2.1.287 → FAIL "mods off: Claude Code <version> is older
     than the 2.1.287 floor; older builds are unsupported". Remediation: update Claude Code.
   - **This session.** At `session.start` the module registers its pull tool, which Claude sees as
     `mcp__rate-limits__status`. Look for that name in your own tool list, counting a name
     listed only as a deferred tool. Do not call it.
     - Present → PASS "mod running in this session".
     - Absent → INFO "mods off in this session, or the status tool's registration was refused".
       Say both causes and do not pick one: mods are off here (what turns them off: the
       doesn't-load pointer below), or the organization's policy refused the tool, in which case the module
       writes one `the status pull tool could not register` line to the debug log
       (`claude --debug`).
   - **This machine (not this session).** Optionally run `claude plugin test` from a new empty
     temporary directory and read its message against the table at the pointer below. It reports
     whether mods can load on this build under the settings a fresh process reads, and nothing
     about this session. Label the row "machine-level: mods can load on this build" or
     "machine-level: mods off (<cause the table gives>)", never as this session's state. The row
     is INFO, or UNKNOWN when `claude plugin test` cannot run here.
   - Where mods are off, the guard runs reactive-only there: the StopFailure hook still records,
     and the file updates only from other sessions that run the module.

   - **Pointer**: [api: add a tool](https://code.claude.com/docs/en/plugins/mods/api#add-a-tool)
     (the `mcp__<plugin>__<name>` form),
     [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
     and [the mod doesn't load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#the-mod-doesn%E2%80%99t-load).
   - **As of**: 2026-10-03, Claude Code 2.1.288; the doesn't-load anchor 2026-10-11.
   - **Recheck trigger**: the full tool name form changes, that table changes a message, or the
     minimum version changes.
3. **Snapshot freshness.** The module writes after main-thread tool results, so this check's own
   Bash calls have each given it a chance to write before you read the file. Read the fixed
   contract path `~/.claude/rate-limits/rate-limits.json` and parse it as JSON:
   - `rate_limits` present and `captured_at` within the staleness window the reader contract's
     operable floor fixes (read the value there, never from here; a number restated in this file
     is a copy nothing keeps in step with the contract) → PASS (proactive mode available).
   - Fresh but `rate_limits` absent → INFO: the sessions writing it see no subscription windows
     (API-key or enterprise auth); consumers correctly run reactive-only. Not a defect. The
     module writes `rate_limits` only when its session sees subscription windows, so this row
     needs no source read. The reader contract owns this fail-open rule: the "Snapshot file
     absent, stale, or missing `rate_limits`" row of its "Capability detection (fail-open)"
     table in `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`. Name that row as the owner
     when reporting this result.
   - Absent or stale while step 2 reported mods off, or while `rate_limits_enabled` (step 5)
     is `false` → INFO with that row's wording: no module writes from here. Not a missing
     instrument and not a wiring defect.
   - Absent or stale while step 2 found the mod running and writes are on → FAIL: the module ran
     but its write did not land. Check step 1 (`node`), then the debug log for
     `rate-limits: snapshot write failed` or `rate-limits: snapshot write did not run`,
     then the permissions of `~/.claude/rate-limits/`.
4. **StopFailure hook.** INFO: the hook needs no wiring (it registers via the plugin's
   `hooks/hooks.json`); confirm the plugin is enabled (`/plugin` → Installed). Report whether
   `~/.claude/rate-limits/stop-events.jsonl` exists. Absent just means no rate-limit stop has
   been recorded yet.
5. **Option posture.** Report every option, each as its own row with the value substituted below
   and what that value does, even when every value is UNKNOWN. Never collapse them into one
   "active" or "UNKNOWN" status: a plugin that is
   enabled while its writes or lines are off is the exact state a person is diagnosing when the
   file is stale or the lines are missing.

   | Option | Value | Default | What it does |
   |---|---|---|---|
   | `rate_limits_enabled` | `${user_config.rate_limits_enabled}` | `true` | `false` stops the StopFailure hook's records and the module's snapshot writes; lines, band and status tool continue. |
   | `model_notices` | `${user_config.model_notices}` | `false` | `false` sends Claude no lines and offers no operator-mode suggestions; `true` sends them. |
   | `rate_limit_report_mode` | `${user_config.rate_limit_report_mode}` | `automatic` | `automatic` sends the lines to Claude; `operator` holds them in a turn a person typed and offers them as a prompt suggestion plus a notice row above the prompt. |
   | `rate_limit_line_threshold` | `${user_config.rate_limit_line_threshold}` | `95` | Window use at which Claude gets the threshold line. An opted-in loop lane's pause threshold stays 95 whatever this is. |
   | `rate_limit_approach_pct` | `${user_config.rate_limit_approach_pct}` | `90` | Window use for the one approach line; at or above the threshold, none is sent. |
   | `rate_limit_line_data` | `${user_config.rate_limit_line_data}` | `verdict,percent,window,reset` | What a line carries beside its verdict: `percent`, `window`, `reset`. |
   | `rate_limits_band` | `${user_config.rate_limits_band}` | `false` | `true` draws the band row; `/rate-limits band on` or `band off` sets it for one session. |
   | `rate_limits_toast` | `${user_config.rate_limits_toast}` | `true` | `false` drops the toast when a window nears or reaches the threshold or resets; the transcript line stays. |

   - Any value still showing its literal `${user_config.<name>}` token (unset key, or a Claude
     Code without the substitution) → **UNKNOWN** for that row, never the default stated as fact.
     The module gets every option with the `plugin.json` default filled in; the StopFailure hook
     reads `rate_limits_enabled` from its `CLAUDE_PLUGIN_OPTION_*` variable and treats unset
     as on. The person-inspectable source of truth is this plugin's `pluginConfigs` options block
     in the user `settings.json` (the hook-config-delivery convention,
     <https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/hook-config-delivery/README.md>,
     owns why the declared `default` field is not delivered to hook processes).
   - A `rate_limit_lines_enabled` key left in `pluginConfigs` does nothing; `model_notices`
     replaced it. Report it as INFO, safe to remove.
   - A threshold or approach mark outside 1 to 100, or a `rate_limit_line_data` list with an
     unknown item, reads as that option's default, and the module logs one transcript line naming
     it. Report the value as invalid and the default as what runs. A value of the wrong type (text
     for a number or a switch) stops the module loading: report it with step 2's row.
   - Every option except `rate_limits_enabled` acts only where step 2 found the mod running.
   - A change made now is observed only in a **fresh session**: rerun this check there and report
     the observed value, never an unobserved change.

     - **Pointer**: for when a saved value reaches skill content and hook processes, fetch
       [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
       live.

6. **Directory left by the earlier name** (migration). Read the pre-computed leftover row.
   `(absent)` → PASS. Otherwise FAIL "drift: `~/.claude/rate-limit-guard/` is left from the
   plugin's earlier name" and list its entries. Lanes read the snapshot only at
   `~/.claude/rate-limits/`, so a snapshot there is read by nothing. Change nothing here.
   Remediation: `apply`, which merges its stop record and removes it (see "`apply`" below). A
   session still running the plugin under its earlier name recreates the directory until it ends;
   a later `apply` finishes it.

## `apply` (earlier-name directory only, on explicit request)

Runs when `~/.claude/rate-limit-guard/` exists; otherwise report that there is nothing to move.
Refuse, and change nothing, when either directory, or either `stop-events.jsonl`, is a symbolic
link. Each step that stops keeps the old directory as it is and says why; a later `apply`
finishes it.

1. **A session still running the earlier name.** When any file in `~/.claude/rate-limit-guard/`
   changed within the staleness window the reader contract's operable floor fixes (read it from
   `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`), stop: that session's module rewrites
   the snapshot there and would recreate the directory. This check cannot see an idle session on
   the earlier name; whatever such a session writes later, a later `apply` merges.
2. **The status line.** When the `statusLine` command in effect (user, project and local
   `settings.json`, the most specific scope that sets it) names a path under
   `~/.claude/rate-limit-guard/`, stop and print that command for the operator; never edit a
   settings file.
3. **Known entries only.** List every entry of the old directory, recursively. These are known:
   the snapshot `rate-limits.json`, `stop-events.jsonl`, any `*.lock` and any `*.tmp.*` file
   (rewritten by the module and the hook), and what releases before the module left and nothing
   reads now: `bin/statusline-shim.sh`, `spool/` and its files, `.statusline-tee-path`,
   `.tee-disabled` and `.last-write`. When anything else is there, list it and stop: the
   operator decides what it is.
4. **The stop record.** No old `stop-events.jsonl` (a machine that never hit a rate-limit stop):
   skip to step 5. Otherwise create `~/.claude/rate-limits/` with mode 700 when absent and run this
   block, which holds the hook's own lock in both directories for the whole merge: the same
   `flock -w 2` over `stop-events.jsonl.lock` that `hooks/record-rate-limit-stop.sh` and
   `hook::append_jsonl` in `hooks/hook-utils.sh` take, the old directory's first (fd 8, which a
   session on the earlier name writes under), then the new one's (fd 9), and no lock where `flock`
   is missing, as the hook runs there. The old records go first and the new file's after them,
   because the hook appends newest last and its rotation keeps the last lines. The old file is
   renamed aside before the merged file replaces the new one, and the aside copy is deleted inside
   the block, so no later `apply` can merge it twice:

   ```bash
   old="$HOME/.claude/rate-limit-guard/stop-events.jsonl"
   new="$HOME/.claude/rate-limits/stop-events.jsonl"
   (
     if command -v flock >/dev/null 2>&1; then
       flock -w 2 8 || exit 3
       flock -w 2 9 || exit 4
     fi
     umask 077
     if [ ! -e "$new" ]; then mv -- "$old" "$new" || exit 1; exit 0; fi
     tmp="$new.tmp.$BASHPID" aside="$old.merged.$BASHPID"
     { cat -- "$old" && if [ -s "$old" ] && [ -n "$(tail -c 1 -- "$old")" ]; then printf '\n'; fi &&
       cat -- "$new"; } >"$tmp" && mv -- "$old" "$aside" || { rm -f -- "$tmp"; exit 1; }
     mv -f -- "$tmp" "$new" || { mv -- "$aside" "$old"; rm -f -- "$tmp"; exit 1; }
     rm -f -- "$aside"
   ) 8>>"$HOME/.claude/rate-limit-guard/stop-events.jsonl.lock" \
     9>>"$HOME/.claude/rate-limits/stop-events.jsonl.lock"
   ```

   Exit 3: the old directory's lock stayed held for 2 seconds; exit 4: the new directory's did;
   stop either way. Any other non-zero exit: stop and say the merge failed.
5. **Remove the old directory.** Run this block, which holds the old directory's lock while it
   checks that no `stop-events.jsonl` is there again (a session on the earlier name may have
   written one since step 4) and removes the directory, so no record lands between the check
   and the delete. It removes the whole directory only because step 3 already proved every entry
   in it known:

   ```bash
   dir="$HOME/.claude/rate-limit-guard"
   (
     if command -v flock >/dev/null 2>&1; then flock -w 2 8 || exit 3; fi
     if [ -e "$dir/stop-events.jsonl" ] || [ -L "$dir/stop-events.jsonl" ]; then exit 4; fi
     rm -rf -- "$dir" && [ ! -e "$dir" ]
   ) 8>>"$HOME/.claude/rate-limit-guard/stop-events.jsonl.lock"
   ```

   Exit 3: the lock stayed held for 2 seconds; stop. Exit 4: a session wrote a stop record there;
   stop and say a later `apply` merges it. Any other non-zero exit: stop and say the removal
   failed. Report what moved or merged, with the line counts, and what was removed.

A second `apply` finds nothing to move and changes nothing; say so.

## Uninstalling

Uninstalling the plugin removes the cache directory, not the files under
`~/.claude/rate-limits/`. Consuming lanes then see no fresh snapshot and run reactive-only, as
the reader contract says. To remove the files too, delete `~/.claude/rate-limits/` after the
uninstall.

## What this skill does NOT do

- Write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform setup
  contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace
  repository). Nor `settings.json` (user, project or managed), a wrapper script, or any other
  Claude Code settings file.
- Install `node`, update Claude Code, or install any system package.
- Write or delete anything under `~/.claude/rate-limits/` beyond the `apply` migration's
  `stop-events.jsonl` move or merge. The module and the hook own `rate-limits.json` and
  `stop-events.jsonl`. The migration removes only the earlier-name directory's known entries.
- Edit the sibling `context-usage` plugin's files.
