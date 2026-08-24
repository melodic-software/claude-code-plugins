---
description: "Verify context-budget's external prerequisites on this machine: `node`, which both the always-on settings-write checkpoint hook and the measurement engine depend on; the Claude Code CLI the engine measures against; and the optional Agent SDK that enables exact mode. Then report the effective settings-write-ask toggle. Use when: 'set up context-budget', 'configure context-budget', 'is context-budget working', 'why did the settings-write ask not prompt', 'why is the audit not exact', or an audit run reported a missing prerequisite. Actions: check (read-only verification, default) | apply (point at each remediation; installs nothing). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and reports,
`apply` points at what it found. The warrant is criterion (b), external prerequisites: `node`,
the Claude Code CLI
the engine pins and measures against, and the optional `@anthropic-ai/claude-agent-sdk` that
enables exact mode, none of which a native configuration prompt can see, and each of which setup
can only verify. The `settings_write_ask_enabled` option is a native `userConfig` toggle whose only
stored home is the `pluginConfigs` this contract forbids setup to write, so this
setup is check-only: `apply` installs nothing, writes nothing, and is idempotent by construction.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then points at
each remediation. Both are non-interactive. Never prompt when the action is given.

## `check` (read-only)

The audit skill and its engine are the single source of truth for what this plugin requires:
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/SKILL.md`](../audit/SKILL.md) § Prerequisites and the header of
`${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs`.

**Read it first**. Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

Install nothing.

1. **`node` on `PATH`**. `command -v node`, and report the resolved path and version. This is the
   plugin's one hard prerequisite, and it carries *two* dependents. Report both:
   - The measurement engine is a Node script, so without `node` `/context-budget:audit` cannot
     produce a number and correctly stops rather than estimating.
   - The PreToolUse checkpoint in `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` registers in **exec
     form**, `"command": "node"` with the script in `args`, so Claude Code resolves the bare name
     `node` on `PATH` in the hook's own environment. A hook that fails to launch is non-blocking,
     so an unresolvable `node` means the checkpoint produces no `ask` and says nothing about it.
     That silent gap is exactly what a native configuration prompt cannot tell you: the option can
     read `true` while the hook it gates never runs.

   FAIL when absent. The checkpoint is a checkpoint either way, never a guarantee. A
   `PermissionRequest` hook can allow the call and `disableAllHooks` removes non-managed hooks.
2. **The Claude Code CLI**. `command -v claude` and its `--version`. The engine measures a pinned
   binary. PASS when one resolves; report the absolute path and version, because that stamp is what
   makes a report a claim. INFO when two installs are present. The audit asks which to pin. FAIL
   when none resolves *and* the operator has no `--binary` path to name, since the engine then has
   nothing to measure.
3. **`@anthropic-ai/claude-agent-sdk`** (optional). Probe whether it resolves under
   `${CLAUDE_PLUGIN_DATA}/sdk`. Present: INFO, exact mode is available. Absent: INFO, not a
   defect. The engine degrades to parsing headless `/context` output (display-rounded, resting on
   an undocumented surface, and the record carries both caveats), and to a structured error rather
   than a wrong number when neither mode works.
4. **Settings-write-ask toggle**. Report the effective `${user_config.settings_write_ask_enabled}`
   (an unexpanded token or an empty value means the manifest default `true`). INFO. The rendered
   value is injected when this skill loads, so a change made now is observed only in a **fresh
   session**; say so rather than re-reading it mid-session. When it reads `false`, note that the
   checkpoint is deliberately off and step 1's `node` finding downgrades to INFO for the hook (it
   stays FAIL for the engine).

## `apply` (idempotent)

Run `check`, then point at each resolution. Every prerequisite here is a system tool or an operator
install, and the one option lives in Claude Code's native configuration surface, so `apply` writes
nothing and installs nothing. Re-running it after everything passes changes nothing and reports
"already configured":

- **Missing `node`:** the platform's own install channel (<https://nodejs.org/en/download>). This
  plugin never downloads a runtime. On Windows, confirm the hook's environment resolves the same
  `node` this check did.
- **Missing CLI:** install the Claude Code CLI, or run the audit with an explicit `--binary` path.
- **Exact mode wanted:** print this one-time install, marked as the operator's. It needs network
  access, so this skill offers it and never runs it:

  ```shell
  mkdir -p "${CLAUDE_PLUGIN_DATA}/sdk" && npm install --prefix "${CLAUDE_PLUGIN_DATA}/sdk" @anthropic-ai/claude-agent-sdk
  ```

- **Toggle off (or on):** direct to `/plugin configure context-budget@<marketplace>` (interactive,
  any time). Headless: rerun the install with the new value:
  `claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=true`
  (repeatable per key). Against an already-installed plugin it
  prints `already installed` **and still writes the value**, verified on Claude Code 2.1.240 (a
  non-sensitive option at `user` scope: a non-default value written to an installed plugin, then
  restored). The short-circuit is about the install, not the config write. Re-verify before relying
  on it outside those conditions. A `sensitive` option, or `project`/`local` scope, were not
  covered. Do **not** uninstall to reconfigure: uninstalling drops this plugin's entire stored
  `pluginConfigs` entry, resetting every option in the README's Options reference table to its
  manifest default. `-s` defaults to `user`, so pass the scope `claude plugin list` reports for this
  plugin, and run from that project's directory for a `project`/`local` scope, or the write lands at
  a scope that does not load. This skill never writes user settings or `pluginConfigs`. Afterwards
  rerun `check` **in a fresh session**. The rendered token is injected at skill load. Report
  the observed effective value; never claim an unobserved change.

## What this skill does NOT do

- Run a measurement, attribution, or ledger operation. That is `/context-budget:audit`.
- Install `node`, the CLI, or the Agent SDK, during either `check` or `apply`. Guidance only.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any other Claude Code
  settings surface.
