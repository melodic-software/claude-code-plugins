---
description: "Set up the speech plugin's text-to-speech prerequisites: check reports Python, espeak-ng, the hook-installed Python packages and the Kokoro model files; apply install-model downloads the pinned Kokoro-82M model, tokenizer and English voices (about 340 MB) into the plugin data directory, or the model_dir option's folder. Use when: 'set up speech', 'set up text to speech', 'download the kokoro model', 'is narrate ready', or /speech:narrate stopped with exit 2. Never installs espeak-ng."
argument-hint: "[check|apply] [install-model]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

The plugin owns no consumer-project configuration. Its two `userConfig` options are set through
`/plugin configure`, never by this skill: `model_dir` moves the Kokoro model folder, and
`elevenlabs_model` picks the elevenlabs backend's default model. Its prerequisites have three
owners:

| Prerequisite | Who installs it |
|---|---|
| Python 3.12 or later, Node.js, espeak-ng | The user. espeak-ng is GPL-3.0, so the plugin never installs or ships it. |
| numpy and onnxruntime | The plugin's SessionStart hook, from the hash-locked `requirements.txt`. |
| Kokoro model, tokenizer, voices | `apply install-model` (this skill), from the pinned revision. |

Non-interactive: never prompt. Run the action, report what it printed, stop.

## `check` (read-only, default)

`${CLAUDE_PLUGIN_ROOT}/scripts/check.py` owns every probe. It reads the declared entries in
`${CLAUDE_PLUGIN_ROOT}/prerequisites.json`, so the install hints are never restated here. Run it:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check.py" --data-dir "${CLAUDE_PLUGIN_DATA}" \
  --model-dir '${user_config.model_dir}'
```

Where `python3` is not on PATH, run this and the `assets.py` command below with `python`; the
SessionStart hook accepts either. Keep `--model-dir` exactly as shown, in single quotes; the
scripts handle an unset `model_dir` option ([reference/plugin-options.md](../../reference/plugin-options.md)).

It prints one `PASS` or `FAIL` row per prerequisite, then a summary, and exits 1 when any row
fails. Report the rows as printed. A `FAIL` row carries its remedy: install hints for a tool, the
repair command for the Python packages, or `apply install-model` for the model.

## `apply install-model`

Downloads the files `${CLAUDE_PLUGIN_ROOT}/scripts/kokoro-assets.json` pins, from that revision,
into the `model_dir` option's folder, or `${CLAUDE_PLUGIN_DATA}/models/` when it is unset. Each
file is hashed as it downloads and kept only when its sha256 matches the pin. Files already present
are skipped, so a rerun is safe.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" fetch --data-dir "${CLAUDE_PLUGIN_DATA}" \
  --model-dir '${user_config.model_dir}'
```

It prints the asset folder and exits 0 when every file is present. On a failed download or a hash
mismatch it exits 1 with the file name and reason, and keeps no partial file. Report the folder, or
the error. Then run `check` and report its rows as the observed state.

Bare `apply` has nothing to configure: say so and name `apply install-model`.

`apply` never installs espeak-ng, Python, Node.js or the Python packages. For a missing tool, report
the install hints `check` printed. For the packages, report the repair command `check` printed.

## Next

/speech:narrate <script file>

## Gotchas

- The model files come from huggingface.co (Kokoro-82M, Apache-2.0). A network that blocks it fails
  `apply install-model` with the URL in the error.
- A new pin in `kokoro-assets.json` downloads into a new folder beside the old one. Remove the old
  folder by hand if disk space matters; `check` prints the folder in use.
