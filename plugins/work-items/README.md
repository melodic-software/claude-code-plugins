# work-items

A Claude Code plugin that manages **development work items through a
provider-neutral tracker seam** — a centralized, concurrent-safe alternative to
file-based TODO lists, designed for teams where humans and autonomous agents
pick work from the same queue. The skill core is backend-agnostic; GitHub is the
bound adapter today.

The tracker's capabilities are split across five focused skills (plus a setup
skill). Invoke the one that matches the job (or let Claude invoke it when you ask
about work items, tracked work, or what to do next):

```text
/work-items:track                      # stats dashboard (default)
/work-items:track add "fix the flaky retry test" --type fix
/work-items:work                       # auto-select + claim + execute one item
/work-items:triage 42
/work-items:decompose                  # break the topic's PLAN.md into tickets
/work-items:scan                       # sweep TODO/FIXME/HACK markers
```

## Skills

| Skill | What it does |
|---|---|
| `/work-items:track` | Backlog CRUD — the sub-action router over `stats`, `list`, `add`, `start`, `done`, `due`, `recheck`, `search`, `audit` (default: the stats dashboard). |
| `/work-items:work` | Auto-select one item by priority tiers, claim it race-safe (assignee + lease), and execute it end-to-end. |
| `/work-items:triage` | Evaluate raw intake — issues and unsolicited PRs (a PR is an item with attached code) — through raw → verified → briefed → autonomous-eligible, with an attention view. |
| `/work-items:decompose` | Break a plan/PRD/item into vertical-slice items with AFK/HITL classification and dependency ordering. |
| `/work-items:scan` | Sweep the codebase for TODO/FIXME/HACK markers; resolve or file each. |
| `/work-items:setup` | Seeds the recurring-schedule seam — interviews the consumer, infers candidate items from the repo, writes the tracked `.github/recurring-schedule.json`, and offers the canonical-role → label remap in the tracker binding (re-runnable). |

## `/work-items:track` actions

| Action | What it does |
|--------|--------------|
| `stats` | Dashboard: open/claimed counts, overdue recurring items, category breakdown (the default when invoked bare) |
| `list` / `search` | Filtered listing / full-text search across open + closed items |
| `add` | Create a work item with a label taxonomy, duplicate pre-flight, and an authorization gate against model-initiated filing |
| `start` / `done` | Claim an item / close it with a completion comment and PR linkage |
| `due` / `recheck` | Recurring-schedule checks and cadence advancement (optional consumer infrastructure) |
| `audit` | Detect stale leases, orphaned recurring entries, label hygiene issues |

## The tracker seam

Every tracker operation goes through the **work-item-tracker seam** — the skills
call `tools/work-item-tracker/work-item-tracker.sh <verb>` and the bound
provider adapter executes it (contract:
`tools/work-item-tracker/CONTRACT.md`). Coordination — create, claim
(assignee + lease), renew/reclaim lease, dependency links, sub-items, frontier
selection, single-item fetch — uses seam verbs directly. Operations without a
core verb (filtered listing, search, aggregation, close, label/comment edits)
are provider-specific and route through the bound adapter's operations reference
(GitHub: `tools/work-item-tracker/adapters/github/README.md`). The skill core
inlines no provider commands, so swapping the backend is swapping the bound
adapter, not editing the skills.

## Multi-agent claim protocol

`/work-items:work` and `/work-items:track start` claim an item by **assigning it
and writing a lease comment**, race-safe at the seam via lease-comment identity,
so multiple concurrent agents never grab the same item. A session-start
`reclaim` runs idempotently to recover the stale leases of crashed or abandoned
sessions. Claim assignments always run on the session's own authenticated
identity — never a shared bot — so the race check stays sound.

## Revisit condition

`/work-items:track` holds the backlog-CRUD actions (dashboard, create, claim,
close, recurring checks, audit) as one skill. Decompose it further only when its
description approaches the skill-listing truncation limit, or its lanes diverge
enough that one skill no longer predicts its contents.

## Requirements

- **The work-item-tracker seam.** The consuming repo provides the seam at
  `tools/work-item-tracker/` and binds its active provider in
  `.work-item-tracker.json`. The seam's contract and per-adapter mechanics are
  documented alongside it (`tools/work-item-tracker/CONTRACT.md`).
- **The bound provider's client.** For the GitHub adapter that is the **`gh`
  CLI**, authenticated against the repository's host; the adapter is the only
  thing that leaves the machine.
- **Labels** (optional but recommended): the universal `type:` / `priority:` /
  `status:` / meta groups, plus any project-specific `area:` / `category:` /
  `ecosystem:` groups the repo defines. The taxonomy and discovery command are
  documented in the plugin's `reference/label-taxonomy.md`.
- **Recurring schedule** (optional): a `.github/recurring-schedule.json` in the
  consuming repo enables the `due` / `recheck` actions and the recurring
  selection tiers of `/work-items:work`. Seed or reshape it with
  `/work-items:setup`; everything else works without it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install work-items@melodic-software
```

## Configuration

No `userConfig`. Project-specific behavior routes through the consuming repo's
own surfaces: the bound provider in `.work-item-tracker.json` (including the
optional `config.role_labels` canonical-role → label remap), its labels
(taxonomy discovery through the adapter), its optional recurring schedule file,
its optional rejected-concept ledger (`docs/out-of-scope/`, checked at intake),
and its own `CLAUDE.md` / rules for write-identity policy (e.g. routing tracker
writes through a bot wrapper) and development workflow. The skills degrade
gracefully when any of these are absent.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
