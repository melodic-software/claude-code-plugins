---
description: "Read-only check that explainer-video can render: Python 3.12 or 3.13, the hash-locked ManimCE packages the SessionStart hook installs, ffmpeg and ffprobe. Use when: 'is explainer-video ready', 'check the explainer-video prerequisites', a session-start notice says its packages could not be installed, /explainer-video:produce stops with a repair line, or before a first render. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether Python, ManimCE, ffmpeg and ffprobe are ready. Never installs.
---

## Check

Run the read-only check and report the rows it prints:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pydeps.py check --data-dir "${CLAUDE_PLUGIN_DATA}"
```

It prints one `PASS` or `FAIL` row each for Python, ManimCE, ffmpeg and ffprobe, and exits 1 when a
row fails. A failed ManimCE row carries the repair line, which installs the locked set in the
foreground. When the script says no Python 3.12 or 3.13 is on PATH, report that as the one failure.
When `python3` itself is not found, run the same line with `python`.

Report the rows as printed and stop. Run the repair line only when the user asks for the install.

## Gotchas

On Linux, and for pycairo on macOS, the install builds pycairo and manimpango from source. When the
repair line fails on a missing compiler, `pkg-config`, cairo or pango, say which development
packages the plugin README lists for that platform. Do not install system packages.
