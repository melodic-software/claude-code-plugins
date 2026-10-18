---
description: "Read-only check that the external tools the knowledge plugin declares (node, python, yt-dlp, ffmpeg, ImageMagick and the rest) resolve. Use when a digest skill stops on a missing tool, or before running video-digest, course-digest, docpage-digest or map-corpus. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs check:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs\" check:*)"
metadata:
  workflow-stage: anytime
  summary: Report whether the tools the knowledge plugin declares resolve. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

The check lives in its own skill so the model can invoke it while `setup` stays manual
(`/knowledge:setup` sets `disable-model-invocation: true`, so a subagent cannot reach its `check`).

- **Pointer**: when deciding what a skill's invocation setting can gate, fetch [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) (the `disable-model-invocation` row) live.
- **As of**: 2026-10-18
- **Recheck trigger**: that section adds a per-action invocation setting, or `disable-model-invocation` stops applying to the whole skill.

## Check

Run the shared prerequisites checker over the plugin's `prerequisites.json`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Report its table: one row per declared tool with its status, what degrades without it, and the
install hint. Exit 0 means every required entry resolves; exit 1 means a required entry is missing
or below its version floor; exit 2 means a usage error or a `prerequisites.json` that fails the
schema, which is a bug to report, not a tool to install. Stop after the table.

To scope the report to one skill, add `--for skill:<name>` (for example `--for skill:video-digest`).
The node dependencies that `video-digest` installs on first run are a separate probe: run its
`extraction/preflight.mjs` (see the video-digest Prerequisites section).

## Next

/knowledge:setup apply install-deps

Only when the user explicitly asked to install the node dependencies or Chromium. `install-deps`
provisions only those; yt-dlp, ffmpeg, ImageMagick and other CLI or system-library rows are OS-level
installs, so show the row's install hint instead. A passing check has no successor.

## Gotchas

This skill does not install. A stop notice from a digest skill is not permission to run `apply`.
A missing row is a report: show the row's install hint and let the user run it.
