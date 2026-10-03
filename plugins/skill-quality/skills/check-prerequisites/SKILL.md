---
description: "Read-only report of whether the external tools the skill-quality plugin declares in prerequisites.json resolve, through the shared Node checker. /skill-quality:check lints a skill; this skill checks the plugin's own tools. Use when a skill-quality script stops on a missing tool, or before assuming a lint ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether the tools skill-quality declares resolve. Never installs.
---

## Purpose

Run the read-only check. Do not install anything, and do not edit `prerequisites.json`.

The plugin's `check` skill already means the skill-authoring gate, so the prerequisites check has its own name.

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

A passing check has no successor. For the skill-authoring gate, run `/skill-quality:check`.

## Gotchas

This skill does not install. A script's missing-tool message is not permission to install anything.
