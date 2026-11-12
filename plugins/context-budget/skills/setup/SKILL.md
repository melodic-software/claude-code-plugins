---
description: "Check-only setup: verifies node, the Claude Code CLI and the optional Agent SDK for context-budget, reports the settings-write-ask toggle, and prints each remediation without installing or writing anything."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(node --version*)"
  - "Bash(claude --version*)"
  - "Bash(command -v node*)"
  - "Bash(command -v claude*)"
shell: bash
---

## Pre-computed context

`check`'s `node`, Claude Code CLI and Agent SDK probes ran at load time; read these rows instead
of re-issuing them. A path row shows the resolved path or `absent`; a version row shows what the
first `PATH` match reports, or `unavailable` when none resolves or it fails to run; the SDK row
shows `present`, `absent`, or `unavailable` when the plugin data directory cannot be read:

- `node`: !`command -v node 2>/dev/null || echo absent`
- `node --version`: !`node --version 2>/dev/null || echo unavailable`
- `claude`: !`command -v claude 2>/dev/null || echo absent`
- `claude --version`: !`claude --version 2>/dev/null || echo unavailable`
- Agent SDK: !`d="${CLAUDE_PLUGIN_DATA}/sdk/node_modules/@anthropic-ai/claude-agent-sdk"; if [ -d "$d" ]; then echo present; elif [ -r "${CLAUDE_PLUGIN_DATA}" ]; then echo absent; else echo unavailable; fi`

A `node` or `claude` row reading `[shell command execution disabled by policy]` carries no result:
run that probe via Bash instead. The SDK row is never re-probed: read it as `unavailable`.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository). Every prerequisite is external (`node`, the
Claude Code CLI the engine measures, the optional `@anthropic-ai/claude-agent-sdk` for exact
mode), and the one option, `settings_write_ask_enabled`, is a native `userConfig` toggle stored
only in `pluginConfigs`, which setup may not write. So `check` inspects, reports and points at
each remediation, and there is no `apply`.

No argument or `check` runs the check. Non-interactive; never prompts.

## `check` (read-only)

What this plugin requires is owned by
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`](../audit/SKILL.md) § Prerequisites and the header
of `${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs`. Read it first, and do not copy it
into the report as a second inventory. Then read the pre-computed rows, run the remaining probes,
and report a PASS/FAIL/INFO table with one remediation line per FAIL. Modify nothing; install
nothing.

1. **`node` on `PATH`**: report the resolved path and version. It is the one hard prerequisite,
   with two dependents; report both:
   - The measurement engine is a Node script, so without `node` `/context-budget:audit` stops
     rather than estimating.
   - The PreToolUse checkpoint in `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` registers in exec form
     (`"command": "node"`), resolved on `PATH` in the hook's own environment. With no `node` the
     checkpoint cannot launch and produces no `ask`, while the option can still read `true` (how
     Claude Code treats a hook that cannot start:
     [Hooks, "Exit code output"](https://code.claude.com/docs/en/hooks#exit-code-output)). Name
     that divergence as exactly what a native configuration prompt cannot tell you.

   FAIL when absent. On Windows, `command -v node` is not the hook's environment: a version
   manager can return a per-call path whose directory name contains a process id, which is not
   the persisted Machine or User PATH the hook inherits. FAIL when the only hit is such an
   ephemeral shim, and say so. Report the persisted resolution separately, from
   `[Environment]::GetEnvironmentVariable('Path','Machine')` and `'User'`, not from the current
   process PATH. A non-ephemeral
   in-process hit is INFO beside that result, not a PASS by itself. The checkpoint is never a
   guarantee: other hooks and settings can override or remove it (the limits and their pointers
   are in the "Hook" section of `${CLAUDE_PLUGIN_ROOT}/README.md`).
2. **The Claude Code CLI**: PASS when one resolves; report its absolute path and version, the
   stamp that makes an audit report a claim. INFO when two installs are present (the audit asks
   which to pin). FAIL when none resolves and the operator has no `--binary` path to name.
3. **`@anthropic-ai/claude-agent-sdk`** (optional): read the pre-computed Agent SDK row; never
   probe `${CLAUDE_PLUGIN_DATA}` yourself, or run the audit or its engine to resolve that row.
   Present: INFO, exact mode available. Unavailable: INFO, SDK state unknown; the row is final.
   Absent: INFO, not a defect. Absent or unavailable: the engine degrades to parsing headless
   `/context` output (state both caveats: display-rounded, on an undocumented surface), and to a
   structured error rather than a wrong number when neither mode works.
4. **Settings-write-ask toggle**: report the effective value of
   `${user_config.settings_write_ask_enabled}` (`true` or `false`; an unexpanded token or empty
   value means the manifest default `true`). INFO. A change shows only in a **fresh session**; say
   so rather than re-reading it (when Claude Code substitutes the value:
   [Plugins reference, "Reference a saved value"](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)).
   When it reads
   `false`, note that the checkpoint is deliberately off and step 1's `node` finding downgrades to INFO for
   the hook (it stays FAIL for the engine).

## Remediation guidance (printed by `check`; the operator applies it)

Close by pointing at each resolution. A rerun after everything passes changes nothing and reports
"already configured".

- **Missing `node`:** the platform's own install channel (<https://nodejs.org/en/download>). This
  plugin never downloads a runtime. On Windows, step 1's persisted-PATH check applies, including
  when `command -v node` succeeded on an ephemeral shim.
- **Missing CLI:** install the Claude Code CLI, or run the audit with an explicit `--binary` path.
- **Exact mode wanted:** print this one-time install, marked as the operator's. It needs network
  access, so offer it and never run it:

  ```shell
  mkdir -p "${CLAUDE_PLUGIN_DATA}/sdk" && npm install --prefix "${CLAUDE_PLUGIN_DATA}/sdk" @anthropic-ai/claude-agent-sdk
  ```

  On Windows, print this PowerShell form instead:

  ```powershell
  New-Item -ItemType Directory -Force -Path "${CLAUDE_PLUGIN_DATA}\sdk" | Out-Null; npm install --prefix "${CLAUDE_PLUGIN_DATA}\sdk" @anthropic-ai/claude-agent-sdk <!-- portability-ok: Windows path, not a shell regex -->
  ```

- **Toggle off (or on):** set `settings_write_ask_enabled` through Claude Code's native flow,
  interactively with `/plugin configure context-budget@<marketplace>` or by a headless route, as
  the marketplace's plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Print the route for the operator; never run a headless
  route, because each writes `pluginConfigs`, which this skill never writes, nor user settings.
  Apply the scope and failure-signal caveats in its
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

## Next

`/context-budget:audit`

It takes the stamped baseline once `check` passes.

## What this skill does NOT do

- Measure, attribute, ledger or invoke the audit, even when asked: route to `/context-budget:audit`.
- Install `node`, the CLI, or the Agent SDK.
- Write the plugin cache, Claude Code user settings, `pluginConfigs`, or any other settings
  surface.
