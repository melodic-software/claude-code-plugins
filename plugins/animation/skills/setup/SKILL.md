---
description: "Verify the animation plugin's prerequisites: ffmpeg with the libx264 encoder, ffprobe, Node, playwright-core with Chromium, numpy and opencv at the pinned versions, and the playwright_core option when set. Use when: 'set up animation', 'is animation working', 'check the animation prerequisites', a render or rotoscope script stopped with exit 2 and a remedy line, or before a first rotoscope run. Action: check (read-only, default). Prints a PASS/FAIL/INFO table with one remediation line per FAIL. Check-only: every prerequisite is external."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

This is a **check-only setup** under the plugin contract's carve-out for external prerequisites
setup can only verify (`docs/plugin-philosophy.md`, "Setup is explicit and repeatable"). The
plugin owns no consumer-project configuration; its one `userConfig` option, `playwright_core`, is
set through Claude Code's plugin settings, never written here. Everything else it needs (ffmpeg,
Node, playwright-core and its Chromium, the Python packages) is installed by the operator, so
there is nothing an `apply` could conformingly write.

Non-interactive: never prompt. Run the probe, print the table, stop.

## `check` (read-only)

`${CLAUDE_PLUGIN_ROOT}/scripts/prereq.py` owns every probe, its threshold and its remedy text;
the same rows stop `render.py` and `decode.py` with exit 2 when a tool is missing. Run it, do not
restate it:

```bash
uv run --with-requirements ${CLAUDE_PLUGIN_ROOT}/requirements.txt python \
  ${CLAUDE_PLUGIN_ROOT}/scripts/prereq.py --playwright-core '${user_config.playwright_core}'
```

It prints the PASS/FAIL/INFO table with one remediation line per FAIL and exits 1 when any row
fails. An unset `playwright_core` option (empty, or left as the literal placeholder) is skipped;
a set one gets its own row. Report the table as printed. An INFO on numpy or opencv means a
version other than the pin in `${CLAUDE_PLUGIN_ROOT}/requirements.txt` is installed: scripts run,
but statistics may differ from the shipped pack and regression, so say so.

When `uv` itself is missing, the command above cannot start: report that as the one FAIL, with
the remedy to install uv (<https://docs.astral.sh/uv/>), and run
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/prereq.py` for the tool rows (it needs only the standard
library; numpy and opencv then read FAIL).

Do not install anything, and do not change the `playwright_core` option.

## Next

/animation:rotoscope <clip> <work dir>

## Gotchas

- The Chromium row launches the browser through `capture.mjs --probe`, so it takes a few seconds
  and is the one row that proves playwright-core and its browser resolve together.
- A PASS on the Chromium row with an unset option can come from the working directory or a
  playwright-cli install on PATH: `capture.mjs` owns that lookup order.
