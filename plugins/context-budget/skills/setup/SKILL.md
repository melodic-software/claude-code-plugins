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

`check`'s `node` and Claude Code CLI probes ran at load time; read these rows instead of
re-issuing them. A path row shows the resolved path or `absent`; a version row shows what the
first `PATH` match reports, or `unavailable` when none resolves or it fails to run:

- `node`: !`command -v node 2>/dev/null || echo absent`
- `node --version`: !`node --version 2>/dev/null || echo unavailable`
- `claude`: !`command -v claude 2>/dev/null || echo absent`
- `claude --version`: !`claude --version 2>/dev/null || echo unavailable`

A row reading `[shell command execution disabled by policy]` carries no result: run that probe via
Bash instead.

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
     (`"command": "node"`), resolved on `PATH` in the hook's own environment. A hook that fails to
     launch is non-blocking, so with no `node` the checkpoint silently produces no `ask`, while
     the option can still read `true`. Name that divergence as exactly what a native
     configuration prompt cannot tell you.

   FAIL when absent. On Windows, `command -v node` is not the hook's environment: a version
   manager can return a per-call path whose directory name contains a process id, which is not
   the persisted Machine or User PATH the hook inherits. FAIL when the only hit is such an
   ephemeral shim, and say so. Report the persisted resolution separately, from
   `[Environment]::GetEnvironmentVariable('Path','Machine')` and `'User'`, not from the current
   process PATH. A non-ephemeral
   in-process hit is INFO beside that result, not a PASS by itself. The checkpoint is never a
   guarantee: a `PermissionRequest` hook can allow the call and `disableAllHooks` removes
   non-managed hooks.
2. **The Claude Code CLI**: PASS when one resolves; report its absolute path and version, the
   stamp that makes an audit report a claim. INFO when two installs are present (the audit asks
   which to pin). FAIL when none resolves and the operator has no `--binary` path to name.
3. **`@anthropic-ai/claude-agent-sdk`** (optional): probe whether it resolves under
   `${CLAUDE_PLUGIN_DATA}/sdk`. Present: INFO, exact mode available. Absent: INFO, not a defect;
   the engine degrades to parsing headless `/context` output (display-rounded, on an undocumented
   surface, both caveats recorded), and to a structured error rather than a wrong number when
   neither mode works.
4. **Settings-write-ask toggle**: report the effective value of
   `${user_config.settings_write_ask_enabled}` (`true` or `false`; an unexpanded token or empty
   value means the manifest default `true`). INFO. The value is injected when this skill loads,
   so a change shows only in a **fresh session**; say so rather than re-reading it. When it reads
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

- **Toggle off (or on):** reconfigure through Claude Code's native flow, per the
  [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md),
  which owns the verified-version record: interactive
  `/plugin configure context-budget@<marketplace>`, or headless
  `claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=true`
  (repeatable per key). Print that command; never run it, because it writes `pluginConfigs`.
  - Against an installed plugin it prints `already installed` **and still writes the value**.
  - Do **not** uninstall to reconfigure: that drops the plugin's whole `pluginConfigs` entry,
    resetting every option in the README's Options reference to its manifest default.
  - Pass the scope `claude plugin list` reports for this install (`user`, `project` or `local`).
    `-s` places `enabledPlugins`; the value lands in user settings either way. A different scope
    adds an install record and enables the plugin there. From the home directory the list can
    label one settings file as both `user` and `project`; pass `user`.
  - A rejected value prints a warning yet exits 0, so read the output.
  - Afterwards rerun `check` in a **fresh session**: a same-session `check` still reports the old
    value. Report the observed value, never an unobserved change.

## Next

`/context-budget:audit`

It takes the stamped baseline once `check` passes.

## What this skill does NOT do

- Measure, attribute or ledger: that is `/context-budget:audit`.
- Install `node`, the CLI, or the Agent SDK.
- Write the plugin cache, Claude Code user settings, `pluginConfigs`, or any other settings
  surface.
