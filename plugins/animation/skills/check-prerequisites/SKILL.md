---
description: "Read-only report of whether the external tools the animation plugin declares in prerequisites.json resolve, through the shared Node checker. /animation:setup is the fuller setup report; this skill is the shared checker's. Use when a hook notice says node is missing, or before assuming the animation Python packages were installed. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether the tools animation declares resolve. Never installs.
---

## Purpose

Run the read-only check. Do not install anything, and do not edit `prerequisites.json`.

The plugin has no `check` skill, so the prerequisites check has its own name. A hook notice names it.

## Check

Run the shared checker through its stub, which reports a missing `node` instead of failing to start:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Where there is no `sh` (Windows without Git Bash), run the PowerShell stub with the same arguments instead:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Report the PASS/FAIL rows as a table. On a FAIL, give the install hints the checker printed. Stop.

## Next

A passing check has no successor. For the fuller setup report, run `/animation:setup`.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js.
