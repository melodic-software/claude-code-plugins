# implementation

A Claude Code plugin for the **implementation stage** of a disciplined dev
workflow: execute an approved plan with incremental validation — inline or via
orchestrated worker subagents — abandoning a broken approach early instead of
pushing it to PR review. Two skills, one concern: turning approved plans into
verified code.

| Skill | What it does |
|---|---|
| `/implementation:implement` | Inline execution discipline — mode detection (feature/fix/refactor/config), TDD-by-default cadence, build+test after each logical block, green-checkpoint commits, divergence detection routing back to planning, scope-fence drift detection, phase-boundary handoffs. |
| `/implementation:implement-dispatch` | Orchestrated execution variant — composes scope-fenced worker briefs, dispatches subagents, verifies returns against direct evidence, builds main-side, and handles divergence in autonomous runs via a conservative-option deviations log. |

## Companion stages (separate plugins)

Build/test/lint, testing, and outcome verification were split out of this plugin into
three companion plugins. This plugin invokes them when installed and degrades
gracefully when absent — no hard dependencies:

- **`toolchain`** — `/toolchain:check` runs after each logical block and at completion;
  when the plugin is absent this skill runs the project's own build/test command.
- **`testing`** — `/testing:plan`, `/testing:write`, `/testing:diagnose` for coverage,
  authoring, and failure diagnosis.
- **`verification`** — `/verification:confirm` for outcome verification at the pre-PR
  handoff; when absent, self-verify the outcome against the plan/intent directly.

## Works in any repo

- **Document placement — via the topic-docs seam.** Plan progress marks, the
  autonomous-run `DEVIATIONS.md` log, status summaries, and handoff notes land per the
  marketplace-wide topic-docs convention (`docs/conventions/topic-docs/README.md`;
  plugin binding: `reference/topic-docs.md`): contract documents in
  `<contract_dir>/<slug>/` (default `docs/topics/`), committed on the task branch and
  pruned before merge; working memory in the self-ignoring `<memory_dir>/` (default
  `.work/`). The tracked `.claude/topic-docs.yaml` concern file is the consumer-side
  source of truth — each lifecycle plugin's own setup (`/discovery:setup`,
  `/planning:setup`, `/verification:setup`) offers to write it.
- **Reads your conventions, assumes none.** Testing structure, commit conventions,
  branch policy, and project invariants come from your own `CLAUDE.md` and rules.
- **Cross-plugin refs degrade gracefully.** Companion plugins (`toolchain`, `testing`,
  `verification`, `tdd`, `planning`, `discovery`, `session-flow`, `source-control`) and
  external marketplace skills are invoked when installed and substituted with inline
  guidance when absent; no step blocks on a missing plugin.
- **Self-contained.** All execution-mode context and the topic-docs binding ship inside
  the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`; state and artifacts go to
  your project's own tree per the topic-docs convention above.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install implementation@melodic-software
```

## Migrating from an earlier `implementation`

If you had `implementation` installed before the `0.6.0` split, `build`, `lint`, `setup`,
`test-plan`, `test-write`, `test-e2e`, `test-diagnose`, `verify-changes`, and `verify-improvement`
no longer live here — nine skills moved into the new `toolchain`, `testing`, and `verification`
plugins. `implementation` keeps its name, so the marketplace's `renames` map (which migrates a
renamed or removed plugin automatically) does not apply — install the plugins you relied on:

```shell
/plugin install toolchain@melodic-software      # check (was build), lint, setup
/plugin install testing@melodic-software        # test-plan, test-write, test-e2e, test-diagnose
/plugin install verification@melodic-software   # verify-changes, verify-improvement
```

`/implementation:implement` and `/implementation:implement-dispatch` still run without them —
build/test falls back to the project's own command and outcome verification falls back to
self-verification — but installing the companion plugins restores the full former surface.

## Configuration

Artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file
(see the topic-docs seam above); each lifecycle plugin's own setup (`/discovery:setup`,
`/planning:setup`, `/verification:setup`) interviews for and persists it. This plugin
declares no userConfig options.

## License

MIT (SPDX-License-Identifier: MIT).
