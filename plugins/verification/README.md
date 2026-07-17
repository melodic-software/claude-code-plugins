# verification

A Claude Code plugin for the **verification stage** of a disciplined dev workflow —
prove a change achieved its intended outcome, and prove measurable-improvement claims
against a baseline captured before the change. Two skills, one concern: turning a
green build into confirmed outcomes.

| Skill | What it does |
|---|---|
| `/verification:confirm` | Outcome verification — a mechanical prerequisite gate (delegated to build/lint) followed by intent-match + evidence + verdict, with the criterion auto-detected by change-type (feature / fix / refactor). |
| `/verification:measure` | Measurable-improvement verification — capture a baseline at planning time, re-measure after the change under the same conditions; no baseline → honest "cannot quantify", never fabricated numbers. |

## Works in any repo

- **Delegates the mechanical pass, degrades gracefully.** `/verification:confirm`
  delegates its build/test/lint prerequisite to the `toolchain` plugin's
  `/toolchain:check` and `/toolchain:lint` when installed, and runs the project's own
  ecosystem-native commands otherwise — the STOP-on-fail gate is unchanged, only the
  executor differs. Live-app verification prefers the `testing` plugin's
  `/testing:e2e` when installed and falls back to Claude Code's bundled `/verify` +
  `/run` or a manual orchestrator launch, never silently downgrading to a static check.
- **Never fabricates a measurement.** `/verification:measure` requires a baseline
  captured before the change; with none, it reports an honest "cannot quantify" plus a
  current-state measurement, never an invented delta.
- **Document placement — via the topic-docs seam.** Verification manifests and
  baselines land per the marketplace-wide topic-docs convention
  (`docs/conventions/topic-docs/README.md`; plugin binding: `reference/topic-docs.md`):
  distilled, `verified_at_sha`-keyed manifests are contract-tier in
  `<contract_dir>/<slug>/verification/`; baselines and raw captures are memory-tier in
  the self-ignoring `<memory_dir>/<slug>/`. The tracked `.claude/topic-docs.yaml`
  concern file is the consumer-side source of truth.
- **Self-contained.** Criterion context files, the redaction bar, and the topic-docs
  binding ship inside the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install verification@melodic-software
```

## Configuration

Artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file
(the `toolchain` plugin's `/toolchain:setup` interviews for and persists it). This
plugin declares no userConfig options.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
