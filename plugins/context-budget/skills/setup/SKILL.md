---
description: "Verify context-budget's external prerequisites on this machine: `node`, which both the always-on settings-write checkpoint hook and the measurement engine depend on; the Claude Code CLI the engine measures against; and the optional Agent SDK that enables exact mode. Then report the effective settings-write-ask toggle. Use when: 'set up context-budget', 'configure context-budget', 'is context-budget working', 'why did the settings-write ask not prompt', 'why is the audit not exact', or an audit run reported a missing prerequisite. Check-only: verifies, reports, and points at each remediation; installs nothing and there is nothing setup may write here. Re-runnable and safe."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(node --version*)"
  - "Bash(claude --version*)"
shell: bash
---

## Pre-computed context

`check`'s `node` and Claude Code CLI probes ran at load time. Read these rows instead of
re-issuing them. A path row shows the resolved path, or `absent` when missing; a version row
shows what the first `PATH` match reports, or `unavailable` when none resolves or it fails to run:

- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`
- `node --version`: !`{ node --version 2>/dev/null || echo "unavailable"; }`
- `claude`: !`{ command -v claude 2>/dev/null || echo "absent"; }`
- `claude --version`: !`{ claude --version 2>/dev/null || echo "unavailable"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that probe via
Bash instead.

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration surface contains no
writable artifact, so `check` inspects, reports, and points at each remediation, and no `apply` is
offered because there is nothing it could conformingly write. The warrant is the carve-out's
external-prerequisites class: `node`, the Claude Code CLI the engine pins and measures against,
and the optional `@anthropic-ai/claude-agent-sdk` that enables exact mode, none of which a native
configuration prompt can see, and each of which setup can only verify. The
`settings_write_ask_enabled` option is a native `userConfig` toggle whose only stored home is the
`pluginConfigs` this contract forbids setup to write.

Action routing: no argument or `check` runs the check. Non-interactive, never prompts.

## `check` (read-only)

The audit skill and its engine are the single source of truth for what this plugin requires:
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`](../audit/SKILL.md) § Prerequisites and the header of
`${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs`.

**Read it first.** The requirement list lives there. Do not copy it into the report as a second
inventory. Then read the pre-computed `node` and `claude` rows, run the remaining probes, and
report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

Install nothing.

1. **`node` on `PATH`**. From the pre-computed `node` rows, report the resolved path and version.
   This is the plugin's one hard prerequisite, and it carries *two* dependents. Report both:
   - The measurement engine is a Node script, so without `node` `/context-budget:audit` cannot
     produce a number and correctly stops rather than estimating.
   - The PreToolUse checkpoint in `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` registers in **exec
     form**, `"command": "node"` with the script in `args`, so Claude Code resolves the bare name
     `node` on `PATH` in the hook's own environment. A hook that fails to launch is non-blocking,
     so an unresolvable `node` means the checkpoint produces no `ask` and says nothing about it.
     That silent gap is exactly what a native configuration prompt cannot tell you: the option can
     read `true` while the hook it gates never runs.

   FAIL when absent. On Windows, `command -v node` is not the hook's environment. A version
   manager can return a per-call path whose directory name contains a process id. That path is
   ephemeral: it is not the persisted Machine or User PATH the hook process inherits. FAIL when
   the only hit is an ephemeral shim, and say so. Report the persisted resolution separately, from
   `[Environment]::GetEnvironmentVariable('Path','Machine')` and `'User'`, not from the current
   process PATH. An in-process hit that is not ephemeral is INFO beside that persisted result,
   not a PASS by itself. The checkpoint is a checkpoint either way, never a guarantee. A
   `PermissionRequest` hook can allow the call and `disableAllHooks` removes non-managed hooks.
2. **The Claude Code CLI**. The pre-computed `claude` rows (path and `--version`). The engine
   measures a pinned binary. PASS when one resolves; report the absolute path and version, because
   that stamp is what makes a report a claim. INFO when two installs are present. The audit asks
   which to pin. FAIL when none resolves *and* the operator has no `--binary` path to name, since
   the engine then has nothing to measure.
3. **`@anthropic-ai/claude-agent-sdk`** (optional). Probe whether it resolves under
   `${CLAUDE_PLUGIN_DATA}/sdk`. Present: INFO, exact mode is available. Absent: INFO, not a
   defect. The engine degrades to parsing headless `/context` output (display-rounded, resting on
   an undocumented surface, and the record carries both caveats), and to a structured error rather
   than a wrong number when neither mode works.
4. **Settings-write-ask toggle**. Report the effective value of the settings-write-ask toggle
   (`${user_config.settings_write_ask_enabled}`, `true` or `false`; an unexpanded token or an
   empty value means the manifest default `true`). INFO. The rendered
   value is injected when this skill loads, so a change made now is observed only in a **fresh
   session**; say so rather than re-reading it mid-session. When it reads `false`, note that the
   checkpoint is deliberately off and step 1's `node` finding downgrades to INFO for the hook (it
   stays FAIL for the engine).

## Remediation guidance (printed by `check`; the operator applies it)

Every prerequisite here is a system tool or an operator install, and the one option lives in
Claude Code's native configuration surface (Check-only carve-out, external-prerequisites and
native-`userConfig` classes), so `check` closes by pointing at each resolution rather than
writing. Re-running it after everything passes changes nothing and reports "already configured":

- **Missing `node`:** the platform's own install channel (<https://nodejs.org/en/download>). This
  plugin never downloads a runtime. On Windows, step 1's persisted-PATH check is the one that
  applies, including when `command -v node` succeeded on an ephemeral shim.
- **Missing CLI:** install the Claude Code CLI, or run the audit with an explicit `--binary` path.
- **Exact mode wanted:** print this one-time install, marked as the operator's. It needs network
  access, so this skill offers it and never runs it:

  ```shell
  mkdir -p "${CLAUDE_PLUGIN_DATA}/sdk" && npm install --prefix "${CLAUDE_PLUGIN_DATA}/sdk" @anthropic-ai/claude-agent-sdk
  ```

  On Windows, print this PowerShell form instead:

  ```powershell
  New-Item -ItemType Directory -Force -Path "${CLAUDE_PLUGIN_DATA}\sdk" | Out-Null; npm install --prefix "${CLAUDE_PLUGIN_DATA}\sdk" @anthropic-ai/claude-agent-sdk <!-- portability-ok: Windows path, not a shell regex -->
  ```

- **Toggle off (or on):** reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive
  `/plugin configure context-budget@<marketplace>` any time, or headless
  `claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=true`
  (repeatable per key; replace `<scope>` with the scope `claude plugin list` reports for this
  plugin). Print that command for the operator. This skill never runs it: it writes
  `pluginConfigs`. Against an already-installed plugin it prints `already installed`
  **and still writes the value**. Do **not** uninstall to reconfigure: that drops this plugin's
  entire stored `pluginConfigs` entry, resetting every option in the README's Options reference
  to its manifest default. Pass the scope `claude plugin list` reports for this plugin's install
  (`user`, `project` or `local`). `-s` places `enabledPlugins`; the option value lands in user
  settings either way. A rerun at a scope other than the installed one adds an install record
  and enables the plugin there; the convention's verified-version record holds the measurement.
  When the working directory is the home directory, the list can label one settings file as both
  `user` and `project`; pass `user` there. A rejected value prints a warning yet exits 0,
  so read the output. This skill never writes user settings or
  `pluginConfigs`. Afterwards rerun `check` in a **fresh session**. The rendered token is
  injected at skill load, so a same-session `check` still reports the OLD value; report the
  observed effective value, never an unobserved change.

## Next

`/context-budget:audit`

It takes the stamped baseline once `check` passes.

## What this skill does NOT do

- Run a measurement, attribution, or ledger operation. That is `/context-budget:audit`.
- Install `node`, the CLI, or the Agent SDK. Guidance only.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any other Claude Code
  settings surface.
