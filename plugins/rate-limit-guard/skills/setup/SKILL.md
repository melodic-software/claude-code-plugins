---
description: "Verify the rate-limit-guard plugin on this machine: node, whether its mod runs in this session, the snapshot file's freshness, the StopFailure hook, and every option's effective value. Use when: 'set up rate-limit-guard', 'is rate-limit-guard working', the snapshot file is stale, a consuming loop lane reports guard mode unknown, or after a plugin update. Action: check (read-only, default). Check-only: prints every remediation and never edits settings, scripts or files."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s `node` probe ran at load time. Read this row instead of re-issuing it; it shows the
tool's path when present, or `absent` when missing:

- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run the
`command -v node` probe via Bash instead.

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration surface contains no
writable artifact, so `check` inspects, reports PASS/FAIL/INFO with one remediation line per FAIL,
and no `apply` is offered because there is nothing it could conformingly write. The surfaces that
qualify it:

- **Native `userConfig`**: eight options whose only stored home is the `pluginConfigs` setup must
  never write. Reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure
  rate-limit-guard@<marketplace>` any time, or headless `claude plugin install
  rate-limit-guard@<marketplace> -s <scope> --config <key>=<value>` (repeatable per key). Against
  an already-installed plugin it prints `already installed` and still writes the value. Do **not**
  uninstall to reconfigure: that drops this plugin's entire stored `pluginConfigs` entry,
  resetting every option in the README's Options reference to its manifest default. `-s` defaults
  to `user`; pass the scope `claude plugin list` reports, and run from that project's directory
  for a `project`/`local` scope, or the rerun adds a second install record at the scope passed and
  enables the plugin there; the value itself always lands in user settings. A rejected value
  prints a warning yet exits 0, so read the output.
- **External prerequisites**: `node` and the Claude Code version, which `check` probes and whose
  install is the person's.

The files under `~/.claude/rate-limit-guard/` are runtime-owned plugin data, written by the module
and the StopFailure hook, not an operator-editable surface.

Action routing: no argument or `check` runs the check.

The code is the source of truth for its own behavior. Read `${CLAUDE_PLUGIN_ROOT}/hooks/register.tsx`
and `${CLAUDE_PLUGIN_ROOT}/hooks/record-rate-limit-stop.sh` when a finding depends on what they do,
rather than reciting this file. The consumer-facing constants (snapshot path, threshold, staleness rule)
are owned by `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

1. **`node`.** The pre-computed `node` row. FAIL if absent: the `StopFailure` row in
   `hooks/hooks.json` is exec form, `"command": "node"` with `hooks/exec-bash.mjs` in `args`, so
   without `node` on `PATH` the hook never launches, a launch failure is non-blocking, and no
   rate-limit stop is recorded; and the module writes the snapshot by running
   `node lib/write-snapshot.mjs`, so no snapshot is written either. The module's lines, band row
   and status tool do not need it. Remediation: install Node.js (<https://nodejs.org/en/download>)
   and restart Claude Code. Verified 2026-09-29 against <https://code.claude.com/docs/en/setup>:
   the native `claude` binary does not ship or use Node.js. Recheck when that page says the native
   binary bundles Node or the hook row stops using `node`.
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
       Say both causes and do not pick one: mods are off here (for example `disableAllHooks`,
       `--bare`, Anthropic's remote switch, repeated hooks-worker crashes, or an organization's
       mods policy), or the organization's policy refused the tool, in which case the module
       writes one `the status pull tool could not register` line to the debug log
       (`claude --debug`).
   - **This machine (not this session).** Optionally run `claude plugin test` from a new empty
     temporary directory and read its message against the table at the pointer below. It reports
     whether mods can load on this build under the settings a fresh process reads, and nothing
     about this session. Label the row "machine-level: mods can load on this build" or
     "machine-level: mods off (<cause the table gives>)", never as this session's state.
   - Where mods are off, the guard runs reactive-only there: the StopFailure hook still records,
     and the file updates only from other sessions that run the module.

   - **Pointer**: [api: add a tool](https://code.claude.com/docs/en/plugins/mods/api#add-a-tool)
     (the `mcp__<plugin>__<name>` form),
     [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
     and [the mod doesn't load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#the-mod-doesnt-load).
   - **As of**: 2026-10-03, Claude Code 2.1.288.
   - **Recheck trigger**: the full tool name form changes, that table changes a message, or the
     minimum version changes.
3. **Snapshot freshness.** The module writes after main-thread tool results, so this check's own
   Bash calls have each given it a chance to write before you read the file. Read the fixed
   contract path `~/.claude/rate-limit-guard/rate-limits.json` and parse it as JSON:
   - `rate_limits` present and `captured_at` within the staleness window the reader contract's
     operable floor fixes (read the value there, never from here; a number restated in this file
     is a copy nothing keeps in step with the contract) → PASS (proactive mode available).
   - Fresh but `rate_limits` absent → INFO: the sessions writing it see no subscription windows
     (API-key or enterprise auth); consumers correctly run reactive-only. Not a defect.
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
   and what that value does. Never collapse them into one "active" status: a plugin that is
   enabled while its writes or lines are off is the exact state a person is diagnosing when the
   file is stale or the lines are missing.

   | Option | Value | Default | What it does |
   |---|---|---|---|
   | `rate_limit_guard_enabled` | `${user_config.rate_limit_guard_enabled}` | `true` | `false` stops the StopFailure hook's records and the module's snapshot writes; lines, band and status tool continue. |
   | `rate_limit_lines_enabled` | `${user_config.rate_limit_lines_enabled}` | `true` | `false` sends Claude no lines and offers no operator-mode suggestions. |
   | `rate_limit_report_mode` | `${user_config.rate_limit_report_mode}` | `automatic` | `automatic` sends the lines to Claude; `operator` holds them in a turn a person typed and offers them as a prompt suggestion plus a notice row above the prompt. |
   | `rate_limit_line_threshold` | `${user_config.rate_limit_line_threshold}` | `95` | Window use at which Claude gets the threshold line. The loop lanes' pause edge stays 95 whatever this is. |
   | `rate_limit_approach_pct` | `${user_config.rate_limit_approach_pct}` | `90` | Window use for the one approach line; at or above the threshold, none is sent. |
   | `rate_limit_line_data` | `${user_config.rate_limit_line_data}` | `verdict,window,reset` | What a line carries beside its verdict: `percent`, `window`, `reset`. |
   | `rate_limit_guard_band` | `${user_config.rate_limit_guard_band}` | `false` | `true` draws the band row; `/rate-limit-guard band on` or `band off` sets it for one session. |
   | `rate_limit_guard_toast` | `${user_config.rate_limit_guard_toast}` | `true` | `false` drops the toast when a window nears or reaches the threshold or resets; the transcript line stays. |

   - Any value still showing its literal `${user_config.<name>}` token (unset key, or a Claude
     Code without the substitution) → **UNKNOWN** for that row, never the default stated as fact.
     The module gets every option with the `plugin.json` default filled in; the StopFailure hook
     reads `rate_limit_guard_enabled` from its `CLAUDE_PLUGIN_OPTION_*` variable and treats unset
     as on. The person-inspectable source of truth is this plugin's `pluginConfigs` options block
     in the user `settings.json` (the hook-config-delivery convention,
     <https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-config-delivery/README.md>,
     owns why the declared `default` field is not delivered to hook processes).
   - A threshold or approach mark outside 1 to 100, or a `rate_limit_line_data` list with an
     unknown item, reads as that option's default, and the module logs one transcript line naming
     it. Report the value as invalid and the default as what runs. A value of the wrong type (text
     for a number or a switch) stops the module loading: report it with step 2's row.
   - Every option except `rate_limit_guard_enabled` acts only where step 2 found the mod running.
   - The rendered values are injected when this skill loads, and the module reads its options when
     it loads; Claude Code reloads a module when its options change, so a changed value acts from
     the next event. The StopFailure hook reads its value at session start. Report the observed
     value, never an unobserved change.

## Uninstalling

Uninstalling the plugin removes the cache directory, not the files under
`~/.claude/rate-limit-guard/`. Consuming lanes then see no fresh snapshot and run reactive-only, as
the reader contract says. To remove the files too, delete `~/.claude/rate-limit-guard/` after the
uninstall.

## What this skill does NOT do

- Write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform setup
  contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace
  repository). Nor `settings.json` (user, project or managed), a wrapper script, or any other
  Claude Code settings surface.
- Install `node`, update Claude Code, or install any system package.
- Write or delete anything under `~/.claude/rate-limit-guard/`. The module and the hook own
  `rate-limits.json` and `stop-events.jsonl`.
- Edit the sibling `context-guard` plugin's files.
