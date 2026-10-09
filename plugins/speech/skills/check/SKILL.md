---
description: "Read-only check of the speech plugin's text-to-speech prerequisites: Python 3.12+, Node.js, espeak-ng, the hook-installed numpy and onnxruntime, and the Kokoro model files. Use when: 'narrate stopped with exit 2', 'what is speech missing', 'is text to speech ready', a session-start notice named a speech prerequisite, or before assuming narration will run. Reports each missing prerequisite with its remedy. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(python3 *check.py*)"
  - "Bash(python *check.py*)"
metadata:
  workflow-stage: anytime
  summary: Report each missing speech prerequisite. Never installs.
---

## Purpose

Run the read-only check, report it, and offer the fixes. This skill is the model-invocable check;
`/speech:setup` stays manual because its `apply` downloads files.

## Check

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check.py" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Where `python3` is not on PATH, run the same command with `python`; the SessionStart hook accepts either.

Report the `PASS`/`FAIL` rows and the summary as printed. Each `FAIL` row carries its remedy.
The check installs nothing. After the report, offer each failed row's fix and run it only on the
user's yes in this session; with no one to answer (an unattended run), report and stop.

- `python-packages`: the row's repair line is the plugin's own hash-pinned install, the command
  the SessionStart hook runs. Name it and run it as printed on a yes.
- `espeak-ng`, Python or Node.js: a system install, often with `sudo`. Write the install command
  for this machine's package manager, from the row's install hints, to a script file, show it,
  and run it on a yes with its output going to a log file, then read the log. When it needs a
  password, the user runs the script and the log is read afterwards.
- `kokoro-model`: state the size the row prints and that `/speech:setup apply install-model`
  downloads the pinned files; the user types that command.

## Next

/speech:setup apply install-model

Only when the `kokoro-model` row failed and the user asked to download it. A passing check has no
successor.

## Gotchas

- A failed row or a session-start notice is not consent. Run no fix before the user says yes, and
  run only the fix the row names, never another installer.
- `/speech:setup` is manual-only, so its `apply install-model` cannot be invoked from here; the
  user types it.
