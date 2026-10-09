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

Run the read-only check, report it, and stop. This skill is the model-invocable check;
`/speech:setup` stays manual because its `apply` downloads files.

## Check

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check.py" --data-dir "${CLAUDE_PLUGIN_DATA}" \
  --model-dir '${user_config.model_dir}'
```

Where `python3` is not on PATH, run the same command with `python`; the SessionStart hook accepts either.
Keep `--model-dir` exactly as shown, in single quotes; the script handles an unset `model_dir`
option ([reference/plugin-options.md](../../reference/plugin-options.md)).

Report the `PASS`/`FAIL` rows and the summary as printed. Each `FAIL` row carries its remedy.
Do not run the remedies.

## Next

/speech:setup apply install-model

Only when the `kokoro-model` row failed and the user asked to download it. A passing check has no
successor.

## Gotchas

- Never install espeak-ng, Python or Node.js, and never run the Python package repair command
  yourself. The user runs them.
