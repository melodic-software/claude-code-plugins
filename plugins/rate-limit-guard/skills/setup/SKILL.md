---
description: "Verify the rate-limit-guard plugin on this machine: node, whether its mod runs in this session, the snapshot file's freshness, the StopFailure hook, and every option's effective value. Use when: 'set up rate-limit-guard', 'is rate-limit-guard working', the snapshot file is stale, a consuming loop lane reports guard mode unknown, or after a plugin update. Action: check (read-only, default). Check-only: prints every remediation and never edits settings, scripts or files."
argument-hint: "[check]"
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

A row reading `[shell command execution disabled by policy]` carries no result: run the
`command -v node` probe via Bash instead.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration contains no
writable artifact, so `check` inspects, reports PASS/FAIL/INFO with one remediation line per FAIL,
and no `apply` is offered because there is nothing it could conformingly write. The surfaces that
qualify it:

- **Native `userConfig`**: eight options whose only stored home is the `pluginConfigs` setup must
  never write. Reconfigure through Claude Code's native flow, interactively with
  `/plugin configure rate-limit-guard@<marketplace>` or by a headless route, as the marketplace's
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

The files under `~/.claude/rate-limit-guard/` are runtime-owned plugin data, written by the module
and the StopFailure hook, not an operator-editable surface.

Action routing: no argument or `check` runs the check.

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
     `mcp__rate-limit-guard__status`. Look for that name in your own tool list, counting a name
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
   contract path `~/.claude/rate-limit-guard/rate-limits.json` and parse it as JSON:
   - `rate_limits` present and `captured_at` within the staleness window the reader contract's
     operable floor fixes (read the value there, never from here; a number restated in this file
     is a copy nothing keeps in step with the contract) → PASS (proactive mode available).
   - Fresh but `rate_limits` absent → INFO: the sessions writing it see no subscription windows
     (API-key or enterprise auth); consumers correctly run reactive-only. Not a defect. The module
     writes `rate_limits` only when its session sees subscription windows, so this row needs no
     source read.
   - Absent or stale while step 2 reported mods off, or while `rate_limit_guard_enabled` (step 5)
     is `false` → INFO with that row's wording: no module writes from here. Not a missing
     instrument and not a wiring defect.
   - Absent or stale while step 2 found the mod running and writes are on → FAIL: the module ran
     but its write did not land. Check step 1 (`node`), then the debug log for
     `rate-limit-guard: snapshot write failed` or `rate-limit-guard: snapshot write did not run`,
     then the permissions of `~/.claude/rate-limit-guard/`.
4. **StopFailure hook.** INFO: the hook needs no wiring (it registers via the plugin's
   `hooks/hooks.json`); confirm the plugin is enabled (`/plugin` → Installed). Report whether
   `~/.claude/rate-limit-guard/stop-events.jsonl` exists. Absent just means no rate-limit stop has
   been recorded yet.
5. **Option posture.** Report every option, each as its own row with the value substituted below
   and what that value does, even when every value is UNKNOWN. Never collapse them into one
   "active" or "UNKNOWN" status: a plugin that is
   enabled while its writes or lines are off is the exact state a person is diagnosing when the
   file is stale or the lines are missing.

   | Option | Value | Default | What it does |
   |---|---|---|---|
   | `rate_limit_guard_enabled` | `${user_config.rate_limit_guard_enabled}` | `true` | `false` stops the StopFailure hook's records and the module's snapshot writes; lines, band and status tool continue. |
   | `model_notices` | `${user_config.model_notices}` | `false` | `false` sends Claude no lines and offers no operator-mode suggestions; `true` sends them. |
   | `rate_limit_report_mode` | `${user_config.rate_limit_report_mode}` | `automatic` | `automatic` sends the lines to Claude; `operator` holds them in a turn a person typed and offers them as a prompt suggestion plus a notice row above the prompt. |
   | `rate_limit_line_threshold` | `${user_config.rate_limit_line_threshold}` | `95` | Window use at which Claude gets the threshold line. An opted-in loop lane's pause threshold stays 95 whatever this is. |
   | `rate_limit_approach_pct` | `${user_config.rate_limit_approach_pct}` | `90` | Window use for the one approach line; at or above the threshold, none is sent. |
   | `rate_limit_line_data` | `${user_config.rate_limit_line_data}` | `verdict,percent,window,reset` | What a line carries beside its verdict: `percent`, `window`, `reset`. |
   | `rate_limit_guard_band` | `${user_config.rate_limit_guard_band}` | `false` | `true` draws the band row; `/rate-limit-guard band on` or `band off` sets it for one session. |
   | `rate_limit_guard_toast` | `${user_config.rate_limit_guard_toast}` | `true` | `false` drops the toast when a window nears or reaches the threshold or resets; the transcript line stays. |

   - Any value still showing its literal `${user_config.<name>}` token (unset key, or a Claude
     Code without the substitution) → **UNKNOWN** for that row, never the default stated as fact.
     The module gets every option with the `plugin.json` default filled in; the StopFailure hook
     reads `rate_limit_guard_enabled` from its `CLAUDE_PLUGIN_OPTION_*` variable and treats unset
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
   - Every option except `rate_limit_guard_enabled` acts only where step 2 found the mod running.
   - A change made now is observed only in a **fresh session**: rerun this check there and report
     the observed value, never an unobserved change.

     - **Pointer**: for when a saved value reaches skill content and hook processes, fetch
       [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
       live.

## Uninstalling

Uninstalling the plugin removes the cache directory, not the files under
`~/.claude/rate-limit-guard/`. Consuming lanes then see no fresh snapshot and run reactive-only, as
the reader contract says. To remove the files too, delete `~/.claude/rate-limit-guard/` after the
uninstall.

## What this skill does NOT do

- Write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform setup
  contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace
  repository). Nor `settings.json` (user, project or managed), a wrapper script, or any other
  Claude Code settings file.
- Install `node`, update Claude Code, or install any system package.
- Write or delete anything under `~/.claude/rate-limit-guard/`. The module and the hook own
  `rate-limits.json` and `stop-events.jsonl`.
- Edit the sibling `context-guard` plugin's files.
