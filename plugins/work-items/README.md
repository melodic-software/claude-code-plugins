# work-items

A Claude Code plugin that manages **GitHub Issues as a development work-item
tracker** — a centralized, concurrent-safe alternative to file-based TODO
lists, designed for teams where humans and autonomous agents pick work from
the same queue.

Invoke it with `/work-items:work-items <action>` (or let Claude invoke it when
you ask about issues, tracked work, or what to do next):

```text
/work-items:work-items                 # stats dashboard (default)
/work-items:work-items add "fix the flaky retry test" --type fix
/work-items:work-items work            # auto-select + claim + execute one issue
/work-items:work-items triage 42
```

## Skills

| Skill | What it does |
|---|---|
| `/work-items:work-items` | The tracker itself — the action router below (stats, list, add, work, triage, …). |
| `/work-items:setup` | Seeds the recurring-schedule seam — interviews the consumer, infers candidate items from the repo, and writes the tracked `.github/recurring-schedule.json` (re-runnable). |

## Actions

| Action | What it does |
|--------|--------------|
| `stats` | Dashboard: open/claimed counts, overdue recurring items, category breakdown |
| `list` / `search` | Filtered listing / full-text search across open + closed issues |
| `add` | Create an issue with a label taxonomy, duplicate pre-flight, and an authorization gate against model-initiated filing |
| `work` | Auto-select one issue by priority tiers and execute it end-to-end |
| `start` / `done` | Claim an issue / close it with a completion comment and PR linkage |
| `due` / `recheck` | Recurring-schedule checks and cadence advancement (optional consumer infrastructure) |
| `scan` | Sweep the codebase for TODO/FIXME/HACK markers; resolve or file each |
| `audit` | Detect stale claims/holds, orphaned recurring entries, label hygiene issues |
| `decompose` | Break a plan/PRD/issue into vertical-slice issues with AFK/HITL classification and dependency ordering |
| `triage` | Structured evaluation of incoming issues, with an attention view |

## Multi-agent claim protocol

`work` and `start` use a three-phase **hold → verify → claim** optimistic-lock
protocol built on GitHub comment-ID ordering, so multiple concurrent agents
never grab the same issue. Stale holds and claims are cleaned up by `audit`.
Claim assignments always run on the session's own identity — a shared bot
identity would defeat the collision check.

## Requirements

- **`gh` CLI**, authenticated against the repository's host. All tracker
  operations go through `gh`; nothing else leaves the machine.
- **Labels** (optional but recommended): the universal `type:` / `priority:` /
  `status:` / meta groups, plus any project-specific `area:` / `category:` /
  `ecosystem:` groups the repo defines. The taxonomy and discovery command are
  documented in the skill's `reference/label-taxonomy.md`.
- **Recurring schedule** (optional): a `.github/recurring-schedule.json` in the
  consuming repo enables the `due` / `recheck` actions and the recurring
  selection tiers of `work`. Seed or reshape it with `/work-items:setup`;
  everything else works without it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install work-items@melodic-software
```

## Configuration

No `userConfig`. Project-specific behavior routes through the consuming repo's
own surfaces: its labels (taxonomy discovery via `gh label list`), its optional
recurring schedule file, and its own `CLAUDE.md` / rules for write-identity
policy (e.g. routing tracker writes through a bot wrapper) and development
workflow. The skill degrades gracefully when any of these are absent.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
