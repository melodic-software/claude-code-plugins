# Skill-tool exercise record

Standing record for #3848: whether each skill in this plugin works when invoked
the way a user invokes one (Skill tool or slash path, plugin installed, in a
consumer repository), not when its scripts are run by hand.

## Decision

**Claim:** Two of seven skills have a live Skill-tool pass in this repository
as consumer (`audit-type-debt`, `principles`, plugin 0.1.8, 2026-09-08). The
other five have no live Skill-tool (or slash-path) pass on a later version.
Description triggering is unpaid for every model-invoked skill. `setup` is
model-hidden, so its Skill-tool AC does not apply; slash `/code-metrics:setup`
is the path. Static inspection of the five unpaid bodies finds the same
interpolation tokens the two live passes resolved: `CLAUDE_SKILL_DIR`,
`CLAUDE_PLUGIN_ROOT`, and (on the four remaining `audit-*` skills) the
`git branch --show-current` precompute. No leftover template token other than
those. Defects found in the live pass are tracked separately (#4002, #4003,
#4066, #4067) and are not this item.

**Basis:** issue #3848 comments recording the 0.1.8 Skill-tool outcomes for
`audit-type-debt` and `principles`; skill frontmatter
`disable-model-invocation` (`true` only on `setup`); bodies under
`plugins/code-metrics/skills/*/SKILL.md` as of plugin 0.3.19. The invocation
mode for `setup` is the class that hides a skill from the model entirely
([invocation-mode](../../../docs/conventions/invocation-mode/README.md)).

**As of:** 2026-09-28.

**Recheck:** a live Skill-tool pass of `audit-size`, `audit-complexity`,
`audit-duplication`, or `audit-coverage` (or a slash-path pass of `setup`)
against a named plugin version; a description-triggering pass of any
model-invoked skill; or a body that adds an interpolation token other than
`CLAUDE_SKILL_DIR`, `CLAUDE_PLUGIN_ROOT`, and the git-branch precompute.

## Per-skill table

Consumer for the live rows: this repository, Claude Code on the web, auto
mode, plugin 0.1.8, 2026-09-08. Later rows are static against 0.3.19.

| Skill | Invocation | Rendered body | Permissions | Description triggering |
|---|---|---|---|---|
| `audit-type-debt` | Skill tool, by name | Resolved; no surviving placeholder | Not assessable (auto mode) | Not assessed (invoked by name) |
| `principles` | Skill tool, by name | Resolved; installed copy byte-identical to the tree | No commands, nothing to prompt | Not assessed (invoked by name) |
| `audit-size` | Unpaid | Same tokens as the two live passes | Unpaid | Unpaid |
| `audit-complexity` | Unpaid | Same tokens as the two live passes | Unpaid | Unpaid |
| `audit-duplication` | Unpaid | Same tokens as the two live passes | Unpaid | Unpaid |
| `audit-coverage` | Unpaid | Same tokens as the two live passes | Unpaid | Unpaid |
| `setup` | Slash path only (model-hidden) | Unpaid slash render; tokens `CLAUDE_SKILL_DIR` and `CLAUDE_PLUGIN_ROOT` only, no precompute | Unpaid | Not applicable |

Filed from the live rows, not from this record: #4002, #4003 (type-debt
collector), #4067 (principles wording), #4066 (skill-quality `## Next` gate).

## Eval slice

Each unpaid `audit-*` skill carries eval id 4
`skill-tool-render-has-no-placeholders`. `setup` carries eval id 4
`slash-invoke-render-has-no-placeholders`. Those cases grade the live render
the next pass will produce; they do not substitute for it. `claude plugin eval`
is a paid runner and was not invoked here.
