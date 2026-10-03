---
description: "Read-only report of whether the external tools the toolchain plugin declares in prerequisites.json resolve, through the shared Node checker. /toolchain:check builds and tests a project; this skill checks the plugin's own tools. Use when a toolchain skill stops on a missing tool, or before assuming a build or lint ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether the tools toolchain declares resolve. Never installs.
---

## Purpose

Run the read-only check. Do not install anything, and do not edit `prerequisites.json`.

The plugin's `check` skill already means the build and test run, so the prerequisites check has its own name.

## Check

Run the shared checker through its stub, which reports a missing `node` instead of failing to start:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Where there is no `sh` (Windows without Git Bash), run the PowerShell stub with the same arguments instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Report the PASS/FAIL rows as a table. A plugin with no `prerequisites.json` prints that it declares no external dependency; report that and stop. On a FAIL, give the install hints the checker printed. Stop.

## Next

A passing check has no successor. To build and test a project, run `/toolchain:check`.

## Gotchas

This skill does not install. A missing project toolchain is reported by `/toolchain:check`, not here.
