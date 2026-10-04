---
description: "Verify the context-guard plugin on this machine: jq, node, whether its mod runs in this session, this session's snapshot freshness, zones.json, every option's effective value, and any retired statusline tee still running beside the mod, with the steps to remove it. Seed or repair ~/.claude/context-guard/zones.json from the shipped defaults. Use when: 'set up context-guard', 'is context-guard working', a consumer reports zone unknown in a live session, or after a plugin update. Actions: check (read-only; never edits settings), apply (writes ONLY ~/.claude/context-guard/zones.json, on explicit request)."
argument-hint: "[check|apply] [defaults]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

Three of `check`'s read-only probes run at load time. Read the values below; do not re-issue them.

`jq` (a path = present, `absent` = missing): !`command -v jq 2>/dev/null || echo "absent"`
`node` (a path = present, `absent` = missing): !`command -v node 2>/dev/null || echo "absent"`
`zones.json` contents, capped at 40 lines, or one token distinguishing an absent file from an unreadable one: !`{ if [ -e "$HOME/.claude/context-guard/zones.json" ]; then cat "$HOME/.claude/context-guard/zones.json" 2>&1 || echo "(present but unreadable)"; else echo "(absent)"; fi; } | head -40`

## Purpose

Narrow-write setup. The plugin's module (`hooks/register.tsx`, a Claude Code mod) writes each
session's snapshot, sends Claude the zone lines, runs the blocking gate, draws the band row and
serves the `mcp__context-guard__status` tool. Nothing about it needs wiring, so `check` inspects
and reports PASS/FAIL/INFO with one remediation line per FAIL. The plugin also owns the machine file
`~/.claude/context-guard/zones.json`, whose schema it defines and whose values the operator may
edit; that owned writable file is what obliges an `apply`, and `apply` writes nothing else.

Versions before this one wrote the snapshot through a statusline tee wired into the user's own
`statusLine`. `check` finds a tee that still runs and prints the steps to remove it; it never edits
a settings file, a script or the plugin cache itself.

Action routing: no argument or `check` runs the check.

The code is the source of truth for its own behavior. Read `${CLAUDE_PLUGIN_ROOT}/hooks/register.tsx`
and `${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh` when a finding depends on what they do, rather
than reciting this file. The consumer-facing constants (snapshot path pattern, staleness rule,
default zone bands, zones.json shape) are owned by
`${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`.

## `check` (read-only)

1. **`jq`**. Read the pre-computed `jq` value. FAIL when it is `absent`: the bash resolver this
   check runs for the zone report (`${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh`) then prints `unknown`, and `apply`
   cannot merge into an existing `zones.json`. The module and the PostCompact marker hook do not
   use jq. Remediation: install jq (<https://jqlang.org/download/>).
2. **`node`**. Read the pre-computed `node` value. FAIL when it is `absent`: the PostCompact marker
   row in `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` runs `node hooks/exec-bash.mjs`, and the module
   writes each snapshot by running `node lib/write-snapshot.mjs`, and Claude Code's native binary
   neither ships nor uses Node (<https://code.claude.com/docs/en/setup>). Without `node` on `PATH`
   the marker does not launch and no snapshot is written, so file readers read `unknown`; report
   that a hook that fails to launch is non-blocking, so nothing else says so. The module's zone
   lines, gate, band row and status tool do not need `node`. Remediation: install Node.js
   (<https://nodejs.org/en/download>) and restart Claude Code. The Node claim was verified
   2026-09-29 against the setup page above; recheck when a Claude Code release note says the
   native binary bundles Node or runs hooks without it, or when that page stops saying the native
   binary needs no Node.
3. **Module state.** The module loads only where mods can.
   - **This session**: the module registers `mcp__context-guard__status` when the session starts.
     Look for that name in your own tool list, deferred tool names included. Present → PASS, the
     mod is running in this session. Absent → INFO "mods off in this session, or the status tool
     was refused by policy" (a refused registration leaves one debug-log line, "context-guard: the
     status tool could not register").
   - Run `claude --version`. Older than 2.1.287 → FAIL "mods off: Claude Code <version> is older
     than the 2.1.287 floor; older builds are unsupported". Remediation: update Claude Code.
   - A separate `claude plugin test` process never sees this session's settings (a
     `disableAllHooks` in this session's settings, `--bare`, worker crashes), so it may only say
     whether mods can load on this build, read against the troubleshoot table at the pointer
     below; never report it as this session's state.
   - Where mods are off, the plugin runs reactive-only there: no zone lines, no gate (blocking mode
     does nothing), no band row, no status tool and no snapshot writes; the PostCompact marker, a
     settings hook, still runs wherever settings hooks do.

   - **Pointer**: [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
     and [the mod doesn't load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#the-mod-doesnt-load).
   - **As of**: 2026-10-03, Claude Code 2.1.288.
   - **Recheck trigger**: that table changes a message, or the minimum version changes.
4. **Retired statusline tee.** Read
   [reference/legacy-statusline-detect.md](reference/legacy-statusline-detect.md), shared with
   rate-limit-guard and synced byte-identical, with `<guard>` = `context-guard` and
   `<plugin-root>` = `${CLAUDE_PLUGIN_ROOT}`. Run its three steps (stamps newer than this version's
   install, cached versions still holding a tee, the three wiring routes) and report each finding
   as that file classifies it. Reading settings, scripts and the plugin cache is all this step
   does.
   - **Any finding** (a running tee, files it left behind, a cached version that still carries one,
     or a wiring route): read [reference/unwrap-before-compose.md](reference/unwrap-before-compose.md)
     with `<guard>` = `context-guard` and print its steps for the person to run: the `statusLine`
     value with every guard shim and tee removed and the person's own renderer kept byte for byte,
     the wrapper-script lines to remove, the files to delete, and the restart. Print the edited
     value itself, worked out by that file's rules, never a script to compute it.
   - **The `statusLine` naming a shim or tee lives in managed settings**: name that file, say the
     person cannot change it from here, and route them to the policy administrator; print no edit
     for it.
   - **No finding**: PASS. Say nothing about the person's own status line: it is theirs, and the
     plugin no longer reads it.
5. **Live-session snapshot freshness**. This session's id is `${CLAUDE_SESSION_ID}`. The module
   writes after every tool call, so this check's own Bash calls have each given it a chance to
   write before you read the file. Probe
   `~/.claude/context-guard/context/${CLAUDE_SESSION_ID}.json`:
   - Exists and `captured_at` is within the reader contract's 10-minute staleness window → PASS
     (zone-informed consumers get real data). Also report the zone:
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/context-zone.sh" ${CLAUDE_SESSION_ID}`.
   - Fresh but `used_percentage` or `current_usage` null → INFO: the state before the session's
     first response or right after `/compact`; the resolver correctly answers `unknown`. Not a
     defect.
   - Absent or stale while step 3 reported mods off → INFO "mods off": no module runs here to
     write it, and readers take their conservative path. Not a missing instrument and not a
     wiring defect.
   - Absent or stale while step 3 found the mod running → FAIL: the module ran but its write did
     not land. Check step 2 (`node`), then the debug log for "context-guard: snapshot write failed"
     or "context-guard: snapshot write did not run", then the permissions of
     `~/.claude/context-guard/context/`.
   - If the literal string `${CLAUDE_SESSION_ID}` appears unexpanded above, report that this
     Claude Code version lacks the substitution and consumers will take the conservative path;
     probe the newest file in `~/.claude/context-guard/context/` instead, labeled as such.
6. **zones.json state**, a read-only report over the pre-computed `zones.json` value: absent
   (shipped defaults in effect, percentage 50/75 plus the window-class token bands; valid
   zero-config state, not a defect), present and valid
   (report the bands in effect, both shapes), or present with a malformed shape (report per
   shape: the resolver validates percentage keys and `token_bands` independently and falls back
   per shape with a stderr notice; a percentage-only file without `token_bands` is valid, with
   shipped token bands silently in effect; remediation: `apply`). A `(present but unreadable)`
   token, or a `cat:` error in place of the contents, is the fourth state: the file exists and
   cannot be read, which is a defect the absent branch would hide. Report the read error and route
   the operator to the file's permissions, not to `apply`. Also report the module's keys when
   present (`approach_margin`, `actions`, `thresholds`; the reader contract's "Zones"
   section defines them); an absent or invalid one means its default, never a defect. The module
   resolves zones with the same bands from the live session, so a machine with no snapshot files
   still gets lines.
7. **Option posture**. Report every option, each as its own row with the value substituted below
   and what that value does. Never collapse them into one "active" status: a plugin that is
   enabled while its kill switch is off, or whose lines are off, is the exact state an operator is
   diagnosing when lines or gating are missing.

   | Option | Value | What it does |
   |---|---|---|
   | `context_guard_hooks_enabled` | `${user_config.context_guard_hooks_enabled}` | `false` → **INERT**: the module sends no lines and gates nothing, and the PostCompact marker hook exits at once. Snapshot writes, the band row and the status tool continue. |
   | `zone_lines_enabled` | `${user_config.zone_lines_enabled}` | `false` → no lines to Claude and no operator-mode suggestions; the gate, band and writes continue. |
   | `zone_report_mode` | `${user_config.zone_report_mode}` | `automatic` sends the lines to Claude; `operator` holds them in a turn a person typed and offers them as a prompt suggestion plus a band notice. |
   | `zone_line_data` | `${user_config.zone_line_data}` | The figures a line carries beside its zone (`percent`, `tokens`, `window`); `zone` alone means none. |
   | `zone_hook_mode` | `${user_config.zone_hook_mode}` | `advisory` leaves the gate inert while the lines run; `blocking` (or a `block` action in `zones.json`) arms it. |
   | `zone_gate_grace_calls` | `${user_config.zone_gate_grace_calls}` | Matched calls allowed in a blocked zone before the gate denies. |
   | `zone_block_unattended` | `${user_config.zone_block_unattended}` | `post-compaction`: headless, loop, schedule and notification turns get only the post-compaction block; `same-as-typed`: they are blocked as typed turns are. |
   | `context_guard_band` | `${user_config.context_guard_band}` | `false` hides the band row; `/context-guard:band` shows or hides it for one session. |

   - Any value still showing its literal `${user_config.<name>}` token (unset key, or a Claude
     Code without the substitution) → **UNKNOWN** for that row, never the default stated as fact.
     Say which source was read: the module gets every option with the `plugin.json` default filled
     in, and the PostCompact marker hook applies its own in-script default (on). The
     operator-inspectable source of truth is this plugin's `pluginConfigs` options block in the
     user `settings.json` (the hook-config-delivery convention,
     <https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-config-delivery/README.md>,
     owns why the declared `default` field is not delivered to hook processes).
   - A `zone_gate_grace_calls` that is not a whole number from 0 to 999999999, or a
     `zone_line_data` item outside the four words, reads as that option's default, and the module
     logs one transcript line naming it at session start. Report the value as invalid and the
     default as what runs.
   - An armed set with an advisory gate is a different runtime state from an inert set, and only
     one of the two is a defect. Every option acts only where step 3 found the mod running, except
     that the kill switch also turns off the PostCompact marker hook, a settings hook that can run
     where mods are off.
   - The module reads its options when it loads, and Claude Code reloads a module when its options
     change, so a changed value acts from the next event. The marker hook reads its value at session
     start.

## `apply` (writes only `~/.claude/context-guard/zones.json`, on explicit request)

Seed or refresh `~/.claude/context-guard/zones.json` from the shipped defaults
(`smart_max_used_percentage: 50`, `acceptable_max_used_percentage: 75`, and the window-class
`token_bands`, the reader contract owns these numbers; read them from
`${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md` rather than this file if they ever disagree).
The `defaults` argument changes only how a present file is treated:

1. **File absent**. Create the directory if needed and write exactly:

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

2. **File present**. Behavior is mode-explicit, never ambiguous:
   - `apply` (no argument): repair-only. Valid recognized band values are left untouched and
     reported; recognized keys that are missing or invalid (non-numeric, inverted, out of range; for `token_bands`, invalid per the reader contract's per-shape validity rules) are set to the
     shipped defaults. An absent `token_bands` is repaired by adding the shipped token bands
     (absence is valid zero-config for the resolver, but the seeded SSOT should carry the full
     tunable surface). An operator's custom-but-valid thresholds are never overwritten by a
     bare `apply`.
   - `apply defaults`: set all recognized band keys (both percentage keys and `token_bands`) to
     the shipped defaults explicitly. This converges forward to a known state; it is not teardown,
     and it never removes the file or any key it does not recognize.
   - Both modes **preserve every unrecognized key semantically**: same keys, same JSON values
     (the file is a shared SSOT the operator's own tools may extend). The module's own keys
     (`approach_margin`, `actions`, `thresholds`) are kept the same way. Preservation is
     value-level, not lexical: a `jq` merge reserializes the document, so formatting and escape
     spellings may normalize (`"blue"` → `"blue"`); consumers of this file must parse it as
     JSON, never depend on its raw bytes. Use `jq` to merge so the result stays valid JSON. If
     `jq` is absent while the file exists, FAIL with the jq install remediation
     (<https://jqlang.org/download/>) instead of attempting a merge, never risk clobbering the
     operator's keys with a jq-less rewrite. (Step 1's template write needs no jq.)
3. **Idempotent**, a second identical `apply` produces no content change; say so.
4. **Report exactly what was written** (old bands → new bands, unrecognized keys preserved), and
   remind that consumers re-read the file on their next zone decision. No restart needed.

`apply` never touches `settings.json`, the snapshot directory, or anything in
`~/.claude/context-guard/` other than `zones.json`.

## Uninstalling

Uninstalling the plugin removes the cache directory, so the module stops and nothing writes new
snapshots. The operator's directory `~/.claude/context-guard/` (`zones.json`, the snapshots and the
compaction markers) stays, and removing it is safe at any time; readers then read `unknown` and take
their conservative path.

One order matters, and only while `check` step 4 still finds a `statusLine` naming
`~/.claude/context-guard/bin/statusline-shim.sh`: apply that step's unwire edit first, then remove
the directory. Deleting the directory while the wiring still names the shim leaves the status line
invoking a missing file: `bash <missing-path>` exits 127 and the whole status line goes down. Report
both steps together, in that order, when asked how to back this out and a shim is still wired.

## What this skill does not do

- Write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform setup
  contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the marketplace
  repository). Nor `settings.json` (user or project), a status line script, or any other Claude
  Code settings surface; the unwire steps are the person's to run.
- Install `jq`, `node` or any system package.
- Write to the snapshot directory `~/.claude/context-guard/context/`; the module owns those files,
  and the unwire steps that delete the retired tee's leftovers there are printed, not run.
- Write anywhere outside `~/.claude/context-guard/zones.json`, including the sibling
  `rate-limit-guard` directory.

## Spoke paths

[reference/legacy-statusline-detect.md](reference/legacy-statusline-detect.md) (step 4's detector)
and [reference/unwrap-before-compose.md](reference/unwrap-before-compose.md) (its unwire steps) are
shared with rate-limit-guard and write this plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`, and this plugin's name as `<guard>`, which is `context-guard`. Put those
values in place of the placeholders before running a command or writing one into a brief. The files
arrive through the Read tool as plain bytes, so a `${…}` token in them would reach the Bash tool
unsubstituted, and the Bash tool's environment has no `CLAUDE_PLUGIN_ROOT` to expand it from.
Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves>, verified
2026-09-30; recheck when that table adds supporting files to where a `${…}` reference resolves.
