# verification

A Claude Code plugin for the **verification stage** of a disciplined dev workflow. It proves a change achieved its intended outcome, and proves measurable-improvement claims
against a baseline captured before the change. Three skills, one concern: turning a
green build into confirmed outcomes.

| Skill | What it does |
|---|---|
| `/verification:confirm` | Outcome verification, a mechanical prerequisite gate (delegated to build/lint) followed by intent-match + evidence + verdict, with the criterion auto-detected by change-type (feature / fix / refactor). |
| `/verification:measure` | Measurable-improvement verification. Capture a baseline at planning time, re-measure after the change under the same conditions; no baseline → honest "cannot quantify", never fabricated numbers. |
| `/verification:setup` | Report where verification artifacts land. Check-only: nothing is configured or written. Re-runnable. |

## Works in any repo

- **Delegates the mechanical pass, degrades gracefully.** `/verification:confirm`
  delegates its build/test/lint prerequisite to the `toolchain` plugin's
  `/toolchain:check` and `/toolchain:lint` when installed, and runs the project's own
  ecosystem-native commands otherwise. The STOP-on-fail gate is unchanged; only the
  executor differs. Live-app verification prefers the `testing` plugin's
  `/testing:run-e2e` when installed and falls back to Claude Code's bundled `/run` or a
  manual orchestrator launch, never silently downgrading to a static check.
- **Never fabricates a measurement.** `/verification:measure` requires a baseline
  captured before the change; with none, it reports an honest "cannot quantify" plus a
  current-state measurement, never an invented delta.
- **Document placement, via the artifact protocol.** Verification manifests, baselines and
  raw captures land per the plugin's lifecycle artifact protocol
  (`reference/artifact-protocol.md`): in the self-ignoring `<memory_dir>/<slug>/` (default
  `.work/<slug>/`), never committed. Distilled, `verified_at_sha`-keyed manifests are pasted into
  the pull request body or the linked issue.
- **Self-contained.** Criterion context files ship inside the plugin and
  are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install verification@melodic-software
```

## Configuration

Artifact placement is fixed by the artifact protocol, so nothing needs configuring.
`/verification:setup check` reports the effective memory root read-only. This plugin declares no
userConfig options.

## License

MIT (SPDX-License-Identifier: MIT).
