# Design resolution — general-improvement-skill

outcome: early-exit
tier: B (light design)
date: 2026-08-17

## Reason

The build artifact is a prose-component plugin (markdown skill + JSON manifests) with no new
code types. The interface-design work a `/planning:design` pass would do was already performed
by the upstream stages: the interview's frontier rounds designed the skill's contract against
named alternatives (router vs finder vs hybrid; hard caps vs adaptive prompt-tunable controls;
one skill vs two), and the research stage grounded every external mechanism. The component
shape itself is fully constrained by fleet conventions (docs/PLUGIN-PHILOSOPHY.md placement +
naming rules, docs/MIGRATION-PLAYBOOK.md publish gate, skill-quality:check schema).

## Component sketch (the "type sketch" equivalent)

```text
plugins/improvement/
  .claude-plugin/plugin.json          # noun name, semver, schema-pinned manifest
  README.md                           # incl. routine-wrapper guidance (prompt-as-tuning-surface)
  CHANGELOG.md
  skills/find/
    SKILL.md                          # /improvement:find — contract + workflow
    context/hotspots.md               # git churn x indentation-complexity recipe (plain git/POSIX)
    context/ci-health.md              # /actions/runs recipe + access-path probe ladder
    context/ranking.md                # WSJF-style value-to-effort + evidence-strength confidence
    context/unattended.md             # caller-declared routine contract (tech-debt-sweep C1 alignment)
    evals/evals.json (+ fixtures/)
.claude-plugin/marketplace.json       # + one entry (./plugins/improvement, taxonomy category)
```

Config surface: `.claude/improvement.md` (team) + `~/.claude/improvement.md` (user-global),
same cascade pattern as codebase-health — evidence-source declarations + churn exclusions.
