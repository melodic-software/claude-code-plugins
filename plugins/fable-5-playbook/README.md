# fable-5-playbook

A Claude Code plugin that ships Claude Fable 5's operating doctrine as an
on-demand knowledge skill — introspected standing instructions written by
Fable 5 about its own failure modes, not generic best practice. Invoking the
skill arms the current session: the core doctrine becomes standing
instructions immediately, and twelve chapters load on demand at their trigger
moments.

Invoke it with `/fable-5-playbook:fable-5-playbook` (bare to arm the session,
`full` to preload every chapter before a long autonomous run, or a chapter
name to read one now), or let Claude load it when you ask it to operate at
playbook level.

## What it provides

- **Core doctrine** — a distillation of every chapter in operating-loop order:
  ground truth and checking, thinking, framing, planning, building, debugging,
  delegating, gates, talking, recovery, context economy, and boundaries.
- **Twelve trigger-routed chapters** under `context/` — calibration,
  reasoning-moves, problem-framing, planning, execution, debugging,
  orchestration, verification, communication, recovery, context-economy, and
  trust-and-authority — each owning its rules' thresholds and exceptions.
- **Model adaptation** — `context/opus-adaptation.md` maps a non-Fable model's
  documented defaults against the author's and gives the standing
  self-corrections the playbook assumes (calibrated for Claude Opus 4.8).

The playbook governs *how* the model works, never *what* the work is: live
user requests, operator configuration, and the consuming repository's own
convention files always outrank it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install fable-5-playbook@melodic-software
```

## Configuration

This plugin has no `userConfig`. It is a pure knowledge skill: nothing to
configure, no scripts, no state, no network access.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
