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
/work-items:scan-todos                 # sweep TODO/FIXME/HACK markers
```

## Skills

| Skill | What it does |
|---|---|
| `/work-items:track` | Backlog CRUD — the sub-action router over `stats`, `list`, `add`, `start`, `done`, `due`, `recheck`, `search`, `audit` (default: the stats dashboard). |
| `/work-items:work` | Auto-select one item by priority tiers, claim it race-safe (assignee + lease), and execute it end-to-end. |
| `/work-items:triage` | Evaluate raw intake — issues and unsolicited PRs (a PR is an item with attached code) — through raw → verified → briefed → autonomous-eligible, with an attention view. |
| `/work-items:decompose` | Break a plan/PRD/item into vertical-slice items with AFK/HITL classification and dependency ordering. |
| `/work-items:scan-todos` | Sweep the codebase for TODO/FIXME/HACK markers; resolve or file each. |
| `/work-items:setup` | `check` inspects the tracked `.github/recurring-schedule.json`, the jq/tracker-seam entry gates, and the recurring-maintenance role label read-only; `apply` binds the provider, writes the empty schedule skeleton, and offers the canonical-role → label remap in the tracker binding (re-runnable). Seeding actual rows — inferring candidate items from the repo and interviewing per item — is opt-in via `apply --seed-schedule` or an offer that recommends skipping; a schedule that already carries items is offered updates as before. |

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

Every tracker operation goes through the **work-item-tracker seam**, which ships
bundled with this plugin. The skills resolve the seam dispatcher plugin-dir
canonical with a project-root fallback (`"$TRACKER" <verb>`) and the bound
provider adapter executes it (contract + resolution:
`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`). Coordination — create, claim
(assignee + lease), renew/reclaim lease, dependency links, sub-items, frontier
selection, single-item fetch — uses seam verbs directly. Operations without a
core verb (filtered listing, search, aggregation, close, label/comment edits)
are provider-specific and route through the bound adapter's operations reference
(GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md`). The skill core
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

- **Bash + jq.** The skills' inline mechanics are POSIX-shell (`jq`, `mktemp`,
  `git grep`, `date`) — on native Windows they run under Git Bash (install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)),
  and `jq` is a separate install there
  ([download](https://jqlang.org/download/)). `jq` is required for
  correctness: when it is missing, stop and surface that remediation instead
  of improvising a parse.
- **The work-item-tracker seam.** The plugin **ships** the seam (dispatcher,
  `lib/`, and the `github`, `local-markdown`, and `jira` adapters) under
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/`; the consuming repo only declares
  its active provider in `.work-item-tracker.json` (run `/work-items:setup`). A repo
  may add or shadow an adapter consumer-local at
  `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/`. The seam's
  contract and per-adapter mechanics are documented in
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`.
- **The bound provider's client.** For the GitHub adapter that is the **`gh`
  CLI**, authenticated against the repository's host; the adapter is the only
  thing that leaves the machine.
- **Labels** (optional but recommended): the universal `type:` / `priority:` /
  `status:` / meta groups, plus any project-specific `area:` / `category:` /
  `ecosystem:` groups the repo defines. The taxonomy and discovery command are
  documented in the plugin's `reference/label-taxonomy.md`.
- **Recurring schedule** (optional): a `.github/recurring-schedule.json` in the
  consuming repo enables the `due` / `recheck` actions and the recurring
  selection tiers of `/work-items:work`. Inspect it with `/work-items:setup check`;
  `/work-items:setup apply` writes the empty skeleton, and
  `/work-items:setup apply --seed-schedule` seeds or reshapes actual rows.
  Everything else works without it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install work-items@<marketplace>
```

## Configuration

`work_dispatch_concurrency_cap` caps the concurrent dispatch waves autonomous
`/work-items:work` allows per item. When set, `/work-items:work` threads it into
`/implementation:implement-dispatch` as that skill's `--wave-cap` ceiling; left
unset (its default state — the key declares no manifest default), it lets
`/implementation:implement-dispatch` apply its own internal 3–5 wave default.
The autonomous per-cycle item budget is a separate, driving-loop concern — the
`work-loop` lane's adaptive item cap (`work_loop_item_cap_start` / `_ceiling` /
`_floor`, plus `work_loop_frontier_item_cap_ceiling`), enforced by the loop
body's own arithmetic. `work_loop_no_progress_threshold` (default 3) sets how
many consecutive no-progress cycles the lane tolerates before raising its
stall escalation — it escalates and keeps looping, never stops on a stall.

`lane_instance` is this machine's writer identity for loop-lane telemetry. It
suffixes each lane's telemetry sentinel marker
(`work-items:work-loop@<id>`), so concurrently running lane instances each own
their own status comment and none can overwrite another's durable state. Absent,
it is the sanitized lowercased hostname; two lanes on one machine each need an
explicit value, since the id must be distinct across concurrent instances and
stable across restarts. It appears verbatim in tracker comments — set an opaque
id if a machine name should not be published in a public tracker.

Everything else is project-specific behavior that routes through the consuming
repo's own surfaces: the bound provider in `.work-item-tracker.json` (including
the optional `config.role_labels` canonical-role → label remap), its labels
(taxonomy discovery through the adapter), its optional recurring schedule file,
its optional rejected-concept ledger (`docs/out-of-scope/`, checked at intake),
and its own `CLAUDE.md` / rules for write-identity policy (e.g. routing tracker
writes through a bot wrapper) and development workflow. The skills degrade
gracefully when any of these are absent.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `lane_instance` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_LANE_INSTANCE` | Writer identity for this machine's loop-lane telemetry, per the loop-lane convention's lane-instance identity rule. It becomes the suffix of the lane's telemetry sentinel marker (`work-items:work-loop@<id>`), so each concurrently running lane instance owns its own comment and none can overwrite another's durable state — including first_drain_complete, whose loss would end one machine's earn-trust ratification gate because a different machine finished a drain. Must match ^\[a-z0-9\]\[a-z0-9-\]{0,31}$, be stable across restarts, and be distinct across concurrent instances; two lanes on one machine each need an explicit value. Absent: the sanitized lowercased hostname. The value appears verbatim in tracker comments — set an opaque id if a machine name should not be published in a public tracker. |
| `work_dispatch_concurrency_cap` | number<br>*min 1* | *(none)* | `CLAUDE_PLUGIN_OPTION_WORK_DISPATCH_CONCURRENCY_CAP` | Maximum concurrent dispatch waves /work-items:work's autonomous execute step allows per invocation (it runs exactly one item per invocation). Give a whole number of waves; a fractional value is floored to whole waves since a wave is discrete. When set, /work-items:work threads it into /implementation:implement-dispatch as that skill's --wave-cap ceiling. Leave unset to let implement-dispatch apply its own internal 3-5 wave default — this key declares no default, so an unset value stays distinguishable from a configured one (which a declared default would collapse into a hard cap). |
| `work_loop_item_cap_start` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_WORK_LOOP_ITEM_CAP_START` | Where the work-loop lane's adaptive per-cycle item cap starts. The cap ramps up by one after three consecutive clean items (never while a rate-limit warning is latched) and drops by one on any dirty item; enforcement is the loop body's own arithmetic. |
| `work_loop_item_cap_ceiling` | number<br>*min 1* | `3` | `CLAUDE_PLUGIN_OPTION_WORK_LOOP_ITEM_CAP_CEILING` | Upper bound the work-loop lane's adaptive item cap can ramp to for non-frontier-tier items. Frontier-tier items are bounded separately by work_loop_frontier_item_cap_ceiling. |
| `work_loop_item_cap_floor` | number<br>*min 1* | `1` | `CLAUDE_PLUGIN_OPTION_WORK_LOOP_ITEM_CAP_FLOOR` | Lower bound the work-loop lane's adaptive item cap can drop to on dirty items. |
| `work_loop_frontier_item_cap_ceiling` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_WORK_LOOP_FRONTIER_ITEM_CAP_CEILING` | Quota guard for frontier-capability-tier items in the work-loop lane: items carrying capability-tier: frontier run at concurrency 1 and their adaptive cap is bounded by this ceiling instead of the general one. Keep it at or below work_loop_item_cap_ceiling. The frontier tier is read from the provider-permissioned label only; absent label = general tier (fail-closed). |
| `work_loop_no_progress_threshold` | number<br>*min 1* | `3` | `CLAUDE_PLUGIN_OPTION_WORK_LOOP_NO_PROGRESS_THRESHOLD` | Consecutive no-progress cycles (actionable work in view, no item advanced and no PR opened) before the work-loop lane raises its stall escalation. The lane escalates and keeps looping; it never stops on a stall. Idle cycles with nothing actionable neither count nor reset. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure work-items@<marketplace>`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install work-items@<marketplace> --config lane_instance=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "work-items@<marketplace>": {
         "options": {
           "lane_instance": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
