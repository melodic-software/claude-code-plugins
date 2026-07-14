# implementation

A Claude Code plugin for the **implementation stage** of a disciplined dev
workflow: execute an approved plan with incremental validation, verify
mechanically (build/test/lint), test at every level, and prove the change
achieved its intended outcome. Eleven skills, one concern — turning plans into
verified code.

| Skill | What it does |
|---|---|
| `/implementation:implement` | Inline execution discipline — mode detection (feature/fix/refactor/config), TDD-by-default cadence, build+test after each logical block, green-checkpoint commits, divergence detection routing back to planning, scope-fence drift detection, phase-boundary handoffs. |
| `/implementation:implement-dispatch` | Orchestrated execution variant — composes scope-fenced worker briefs, dispatches subagents, verifies returns against direct evidence, builds main-side, and handles divergence in autonomous runs via a conservative-option deviations log. |
| `/implementation:build` | Build + test + lint for changed files, auto-detecting affected ecosystems (.NET, Python, TypeScript, Bash, PowerShell, Markdown); resolves each ecosystem's commands through the shared four-rung ladder. |
| `/implementation:lint` | Lint + format checks only — faster than a build cycle, honors each tool's config-file opt-in, `--fix` mode where linters support it; also owns the `yaml` and `cross-cutting` lint surfaces. |
| `/implementation:setup` | Configure the plugin for a repo — interview + infer + write the tracked `.claude/ecosystems/<ecosystem>.yaml` files that `/build` and `/lint` resolve first, and offer the tracked `.claude/topic-docs.yaml` concern file. Re-runnable. |
| `/implementation:test-write` | Test authoring discipline — vertical-slice TDD, test-type selection, naming, placement, fixture patterns, four-pillars assessment. |
| `/implementation:test-plan` | Coverage-gap analysis — classify changed files by required test type, identify gaps, prioritize by regression risk. |
| `/implementation:test-diagnose` | Failing-test diagnosis — failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. |
| `/implementation:test-e2e` | Live app verification — start the app via the project's orchestrator, drive UI/API flows with token-efficient browser automation, capture evidence; includes a non-UI smoke-test playbook (MCP stdio handshake, shell/PowerShell surfaces). |
| `/implementation:verify-changes` | Outcome verification — a mechanical prerequisite gate (delegated to build/lint) followed by intent-match + evidence + verdict, with the criterion auto-detected by change-type (feature / fix / refactor). |
| `/implementation:verify-improvement` | Measurable-improvement verification — capture a baseline at planning time, re-measure after the change under the same conditions; no baseline → honest "cannot quantify", never fabricated numbers. |

## Works in any repo

- **Consumer conventions win — via the ecosystem-commands seam.** `/build` and
  `/lint` resolve each ecosystem's build/test/lint commands through a four-rung
  ladder: your repo's tracked `.claude/ecosystems/<ecosystem>.yaml`
  (authoritative when present, additive over a `~/.claude/ecosystems/`
  user-global base and a `.local.yaml` overlay) → inference → ask → the plugin's
  bundled portable defaults. Run `/implementation:setup` to write those files
  once. The command surface conforms to the marketplace-wide contract at
  `docs/conventions/ecosystem-commands/README.md`
  (schema: `ecosystem.schema.json`); testing structure and commit conventions
  still come from your own `CLAUDE.md` and rules.
- **Document placement — via the topic-docs seam.** Plan progress, verification
  manifests, and baselines land per the marketplace-wide topic-docs convention
  (`docs/conventions/topic-docs/README.md`; plugin binding:
  `reference/topic-docs.md`): contract documents in `<contract_dir>/<slug>/`
  (default `docs/topics/`), committed on the task branch and pruned before merge;
  working memory in the self-ignoring `<memory_dir>/<slug>/` (default `.work/`).
  The tracked `.claude/topic-docs.yaml` concern
  file is the consumer-side source of truth — `/implementation:setup` offers to
  write it.
- **Cross-plugin refs degrade gracefully.** Companion plugins (`tdd`,
  `discovery`, `session-flow`, `playwright`) and external marketplace skills are
  invoked when installed and substituted with inline guidance when absent; no
  step blocks on a missing plugin.
- **Self-contained.** All command tables and context references ship inside the
  plugin; state and artifacts go to your project's own tree per the topic-docs
  convention above.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install implementation@melodic-software
```

## Configuration

Artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file
(see the topic-docs seam above); `/implementation:setup` interviews for and persists
it. This plugin declares no userConfig options.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
