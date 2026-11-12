# work-items

A Claude Code plugin that manages **development work items through a
provider-neutral tracker seam**, a centralized, concurrent-safe alternative to
file-based TODO lists, designed for teams where humans and autonomous agents
pick work from the same queue. The skill core is backend-agnostic; GitHub is the
bound adapter today.

The tracker's capabilities are split across ten focused skills (plus a setup
skill). Invoke the one that matches the job (or let Claude invoke it when you ask
about work items, tickets, issues, tracked work, or what to do next):

```text
/work-items:track                      # stats dashboard (default)
/work-items:track add "fix the flaky retry test" --type fix
/work-items:work                       # auto-select + claim + execute one item
/work-items:triage 42
/work-items:decompose                  # break the topic's PLAN.md into tickets
/work-items:ship                       # macro map over a spec container: status, shape, next step
/work-items:ship run #300              # run the container's ready items under its shape (attended)
/work-items:scan-todos                 # sweep TODO/FIXME/HACK markers
/work-items:onboard-adapter youtrack   # generate an adapter for a tracker with no adapter or seed
/work-items:measure-delivery           # DORA delivery metrics as a weekly team trend
/work-items:morning-brief              # operator's read-only morning view of the repo
```

## Skills

| Skill | What it does |
|---|---|
| `/work-items:track` | Backlog CRUD, the sub-action router over `stats`, `list`, `add`, `start`, `done`, `due`, `recheck`, `search`, `audit` (default: the stats dashboard). |
| `/work-items:work` | Auto-select one item by priority tiers, claim it race-safe (assignee + lease), and execute it end-to-end. |
| `/work-items:work-loop` | Drain the backlog as a self-paced autonomous loop launched via `/loop`: each cycle triages raw intake, admits items through the fail-closed admission gate, runs them through `/work-items:work` under an adaptive cap, and checks the drain exit. Authors PRs, never merges. |
| `/work-items:attend-queue` | Attend the loop-lane human queue: drive escalated items to resolution and list untriaged intake beside them, handing each intake row to `/work-items:triage`. Answers escalations by interview and flips unblocked items autonomous-eligible. Never executes or merges. |
| `/work-items:triage` | Evaluate raw intake, issues and unsolicited PRs (a PR is an item with attached code), through raw → verified → briefed → autonomous-eligible, with an attention view. |
| `/work-items:decompose` | Break a plan/PRD/item into vertical-slice items with AFK/HITL classification and dependency ordering. When a spec container is published and the design behind the plan produced typed artifacts (frontmatter carrying `scope` and `dialect`), each is inlined into the container body as a fenced block plus a one-line provenance note naming the scope and dialect, with no file path; an `integration` design labels two, and both are inlined. Slice bodies are unchanged. |
| `/work-items:ship` | Macro-journey router over one spec container: rollup + scoped frontier, the container's recorded execution shape (per-item PRs vs integration branch → single PR) with that mode's discipline, and the routed next step. `run` works the container's ready items in parallel through `/implementation:implement-dispatch` and lands them one at a time, attended only. Mechanics stay with their owners. |
| `/work-items:morning-brief` | Prints the read-only, `gh`-based operator morning view for the current repo in one pass: open counts per queue label (`needs-triage`, `status: ready`, `needs-owner-decision`, `needs-human`), placing each issue by its Work status value when the repo's `pr-pipeline.yaml` models one, the gh-native merge-ready PR list (non-draft + `mergeStateStatus=CLEAN`, with a clean PR whose head is behind its base marked `UNVERIFIED`), parked `needs-owner-decision` issues with their RECOMMENDED lines, and loop-lane telemetry freshness (per-lane `last-cycle` age + `flags:`). Never mutates anything; the authoritative PR merge gate stays `/source-control:babysit-prs`. |
| `/work-items:scan-todos` | Sweep the codebase for TODO/FIXME/HACK markers; resolve or file each. |
| `/work-items:measure-delivery` | Read-only report of the five DORA delivery metrics (deployment frequency, change lead time, change fail rate, failed deployment recovery time, deployment rework rate) as a team trend from the default branch's git history, never per person. |
| `/work-items:onboard-adapter` | Onboard a tracker this plugin does not bundle: interview to lock the provider's shape, explore the consumer's real instance for the per-instance facts only it can settle, generate a consumer-owned adapter (hardened security skeleton, honest capability manifest, contract-fixed verb scaffolds, conformance binding) into the consuming repo, then verify. The tail half of the hybrid adapter model. Bundled adapters and seeds cover the majors. |
| `/work-items:setup` | `check` inspects the tracked `.github/recurring-schedule.json`, the jq/tracker-seam entry gates, and the recurring-maintenance role label read-only; `apply` binds the provider, writes the empty schedule skeleton, and offers the canonical-role → label remap in the tracker binding (re-runnable). Seeding actual rows, inferring candidate items from the repo and interviewing per item, is opt-in via `apply --seed-schedule` or an offer that recommends skipping; a schedule that already carries items is offered updates as before. |

## Naming

**Work item** is the canonical term. **Ticket** and **issue** are first-class
synonyms for invocation. They appear in the Use-when triggers of the
**item-facing** skills, so phrasing like "add a ticket" or "work the next
issue" routes here, not a rename of the plugin, seam, or surface.

"Item-facing" is the precise scope, and it is narrower than every skill in the
plugin: `track`, `work`, `work-loop`, `triage`, `decompose`, `attend-queue` and
`scan-todos` carry the synonyms because a user says those words to them. The
infrastructure skills (`setup`, `onboard-adapter`) speak in provider and tracker
terms, and `ship` speaks in container and journey terms. Nobody says "add a
ticket" to an adapter generator. Stuffing the tokens into their triggers to
satisfy a fleet-wide claim would make the sentence tidier and the
routing worse, so the claim is scoped instead.

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
`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`). Coordination operations use
seam verbs directly: create, claim (assignee + lease), renew/release/reclaim lease,
dependency links, sub-items, frontier selection, and single-item fetch. Operations without a
core verb (filtered listing, search, aggregation, close, label/comment edits)
are provider-specific and route through the bound adapter's operations reference
(GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md`;
local-markdown: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/local-markdown/README.md`).
The skill core inlines no provider commands, so swapping the backend is swapping the bound
adapter, not editing the skills. CONTRACT.md remains the SSOT for verbs.

## Multi-agent claim protocol

An item is claimed by **assigning it and writing a lease comment**, race-safe at
the seam via lease-comment identity, so multiple concurrent agents never grab the
same item. These skills claim:

- `/work-items:work`, `/work-items:track start` and `/work-items:ship run`,
  before they execute an item.
- `/work-items:triage`, before its first write to an item (a comment, label,
  edge or close), with `--phase triage`, clearing its assignee and releasing the
  claim after its last write.
- `/work-items:work-loop`, through the `/work-items:work` and
  `/work-items:triage` runs it makes.
- `/work-items:attend-queue`, before it writes to a row, with `--phase triage`,
  releasing the claim after the row's disposition. Its `[intake]` rows are left
  to triage's own claim.

A claim lost to another session (exit `7`) skips the item. Read-only listings,
such as the triage attention view and `/work-items:track stats`, never claim.
A session-start
`reclaim` runs idempotently to recover the stale leases of crashed or abandoned
sessions. Claim assignments always run on the session's own authenticated
identity, never a shared bot, so the race check stays sound.

## Revisit condition

`/work-items:track` holds the backlog-CRUD actions (dashboard, create, claim,
close, recurring checks, audit) as one skill. Decompose it further only when its
description approaches the skill-listing truncation limit, or its lanes diverge
enough that one skill no longer predicts its contents.

## Requirements

- **Bash + jq.** The skills' inline mechanics are POSIX-shell (`jq`, `mktemp`,
  `git grep`, `date`), on native Windows they run under Git Bash (install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)),
  and `jq` is a separate install there
  ([download](https://jqlang.org/download/)). `jq` is required for
  correctness: when it is missing, stop and surface that remediation instead
  of improvising a parse.
- **The work-item-tracker seam.** The plugin **ships** the seam under
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/`: the dispatcher, `lib/`, and two bundled
  adapters, `github` and `local-markdown`. The `jira`, `gitea`, and `linear` adapters ship as
  seeds under `seeds/`: `/work-items:setup apply` copies the bound one into the consuming repo,
  which owns the copy from then on. On a re-run, setup fast-forwards a copy nobody edited and
  stops with the diff on one somebody did. The consuming repo declares its
  active provider under the `tracker` key of `<home>/work-items.yaml` in its convention home
  (default `docs/conventions`). A repo-root `.work-item-tracker.json` no longer binds:
  `/work-items:setup apply` copies it under that key. A personal override beside the
  binding (`work-items.local.yaml`) may carry the per-user
  lease TTL and the per-provider auth identity: `auth_email` and `auth_env` for jira, `auth_env`
  for linear, and `auth_env` for gitea. A repo
  may add or shadow an adapter consumer-local at
  `<repo root>/tools/work-item-tracker/adapters/<provider>/` (the root being
  `${CLAUDE_PROJECT_DIR}`, else the git toplevel). `/work-items:onboard-adapter`
  generates one, and no vendored copy of the seam is needed for it to run. The seam's
  contract and per-adapter mechanics are documented in
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`.
- **The bound provider's client.** For the GitHub adapter that is the **`gh`
  CLI**, authenticated against the repository's host; the adapter is the only
  thing that leaves the machine.
- **Labels** (optional but recommended): the universal `type:` / `status:` / meta
  groups, plus any project-specific `area:` / `category:` / `ecosystem:` groups the
  repo defines. The taxonomy and discovery command are documented in the plugin's
  `reference/label-taxonomy.md`.
- **Priority** (optional): an organization `Priority` single-select issue field,
  which triage and `/work-items:track add --priority` write. Where there is no such
  field or the adapter cannot write one, they use the repo's `priority:` labels.
- **Recurring schedule** (optional): a `.github/recurring-schedule.json` in the
  consuming repo enables the `due` / `recheck` actions and the recurring
  selection tiers of `/work-items:work`. Inspect it with `/work-items:setup check`;
  `/work-items:setup apply` writes the empty skeleton, and
  `/work-items:setup apply --seed-schedule` seeds or reshapes actual rows.
  Everything else works without it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install work-items@melodic-software
```

## Configuration

`work_dispatch_concurrency_cap` caps how many worker rows of one plan phase, one
dispatch wave, autonomous `/work-items:work` runs at once per item. When set, `/work-items:work` threads it into
`/implementation:implement-dispatch` as that skill's `--wave-cap` ceiling; left
unset (its default state, the key declares no manifest default),
`/implementation:implement-dispatch` applies its `implement_dispatch_wave_cap` operator option, else its internal
default (its precedence list owns the order). Rows that share a worktree under
worker authority run one at a time. `/implementation:implement-dispatch` sets the authority from the
consuming plan, so the cap changes behavior only under commit authority `orchestrator` with several
rows sharing a worktree.
The autonomous per-cycle item budget is a separate, driving-loop concern, the
`work-loop` lane's adaptive item cap (`work_loop_item_cap_start` / `_ceiling` /
`_floor`, plus `work_loop_frontier_item_cap_ceiling`), enforced by the loop
body's own arithmetic. `work_loop_no_progress_threshold` (default 3) sets how
many consecutive no-progress cycles the lane tolerates before raising its
stall escalation. It escalates and keeps looping, never stops on a stall.
`work_loop_in_flight_stale_days` (default 14) is the age, from the PR's
`createdAt`, past which an open closing PR stops silently excluding its
candidate: the lane escalates it and the drain report names it.

`lane_instance` is this machine's writer identity for loop-lane telemetry. It
suffixes each lane's telemetry sentinel marker
(`work-items:work-loop@<id>`), so concurrently running lane instances each own
their own status comment and none can overwrite another's durable state. Absent,
it is the sanitized lowercased hostname; two lanes on one machine each need an
explicit value, since the id must be distinct across concurrent instances and
stable across restarts. It appears verbatim in tracker comments. Set an opaque
id if a machine name should not be published in a public tracker.

`triage_repro_count` (default 2) and `triage_objection_window_hours` (default 0,
off) have a repository layer as well: the same keys in the consuming repo's
`docs/conventions/work-items.yaml`, checked by
[`schemas/work-items.schema.json`](schemas/work-items.schema.json), win over the
per-user values. Lowest first: the manifest default, `userConfig`, the
repository file. Only `/work-items:triage` reads these two keys, through the bundled
`parse-concern-value.sh`, and reports which layer supplied each value; the
work-loop admission gate reads the window's end from the marker comment triage
posts. A lane that passes `--config-ref <ref>` to triage has the
file read as committed at that ref, so a branch under triage cannot change the
bar it is judged by. The repro count is how many independent reproductions a
bug needs before triage marks it `status: confirmed`. With a window above 0,
triage posts an "Objection window until <UTC>" comment beside the brief of each
item it makes autonomous-eligible; the work-loop lane skips the item until the
window ends and escalates it if a person replies inside the window.

`triage_stale_reporter_info_days` exists only in the repository file and has no
default, so it is off until a repository sets it. When it is set, the
`/work-items:triage` attention view lists each open `needs-reporter-info` item as
a close candidate if its reporter lacks write access and has not replied for
that many days since the last triage note. Listing closes nothing. In an attended
session triage asks once and closes only the candidates the operator says yes
to. A lane or CI run reports the list and never closes.

`ai_disclaimer` (default `false`) takes the same layers, in the same order:
when it resolves `true`, autonomous lanes start each tracker item and comment
they create with the AI disclaimer. The key, its layers and the prefix are
stated once in [`reference/ai-disclaimer.md`](reference/ai-disclaimer.md).

`bug_path.fix_gate` lives only in the repository file and is read from the
default branch, so a branch cannot loosen it. It holds the seven conditions a
bug item passes, in full mode, before `/work-items:work` dispatches a fix:
`confirmed_repro`, `evidence_reviewed`, `no_fix_artifact`, `no_human_claim`
and `root_cause_evidenced` are floors, always on (a `false` is named and
ignored); `before_after_runnable` (default `true`) may be turned off;
`budget_minutes` (default 90) and `scope` (path prefixes, default the paths the
root cause names) bound the fix. A failing condition stops the run with no fix
and no pull request, naming the condition. The work skill's "Fix gate (bugs)"
sub-step says how it is read.

```yaml
bug_path:
  fix_gate:
    before_after_runnable: false
    budget_minutes: 45
```

`triage_cluster` lives only in the repository file and sets how
`/work-items:triage` clusters items that share a signature under one parent, the
only member that can get `agent-ready`. `signatures` lists which shared
signatures count (`error`, `symptom`, `commit`; default all three),
`min_members` how many open items must share one (default 2), and `parent` which
member leads (`oldest-reproduced`, the default, or `oldest`). The defaults are
provisional until tuned on the first 20 clusters.

```yaml
triage_cluster:
  signatures: [error, commit]
  min_members: 3
  parent: oldest
```

`triage_outside_prs` (default `false`) lives only in the repository file. Set it
to `true` when the repository takes requests as pull requests from outside
contributors: the `/work-items:triage` attention view then lists those pull
requests beside the issues. When it is `false`, the view lists only issues. A
pull request named explicitly, as `/work-items:triage <number>`, is triaged
either way.

`work_priority_order` lives only in the repository file: a list of priorities,
highest first, each an org `Priority` issue field option or a `priority:` label
name (`high` and `priority: high` are one rank), defaulting to
`priority: critical`, `priority: high`, `priority: medium`, `priority: low`.
`/work-items:work` ranks the candidates in each selection tier by it, reading
each item's `Priority` field and falling back to its `priority:` label, and the
tier's own order (`next_due`, the guardrails preference, or oldest-first) breaks
ties. The work-loop lane ranks its admitted items the same way before its
`created_at` order. An item with no listed priority ranks last in its tier. Quote
each item, since an unquoted `- priority: high` parses as a mapping and drops
out of the list:

```yaml
work_priority_order:
  - "priority: critical"
  - "priority: high"
  - "priority: medium"
  - "priority: low"
```

The work skill's "Selection Priority" section says how it is read.

`bug_path.mode` also lives only in the repository file. With `full`, the
default, `/work-items:work` runs a bug item through to a fix and a draft pull
request. With `investigate`, it stops after the root cause: it opens no branch,
writes no fix and opens no pull request. Both modes keep one report comment on
the item, edited in place: a status line, the outcome, the reproduction
evidence, the ranked causes, a test-gap line, an instruction to the fixing
agent, the access that was missing and the quoted report. CI mode
(`--issue <n> --ci`) does not read the key and runs a bug item through to a
fix. The work skill's "Bug report" and "Investigate mode" sections say how it
is read.

```yaml
bug_path:
  mode: investigate
```

`verification` and `verification_skills.<skill>` (`off`, `light`, `standard`
or `strict`, default `standard`) also live only in the repository file, and are
read from the default branch through `lib/read-verification.sh`, so a branch
cannot lower them. `/work-items:work` reads them for the bug path's capture
check: at `standard` and `strict` a fresh-context subagent confirms each
reproduction capture shows the named broken state; `light` and `off` dispatch
none and record `verification: skipped (<level>)`. A skill entry beats the
plugin value
([verification level](../../docs/contracts/verification-level/README.md)).

`delivery_deploy_signal` also lives only in the repository file. It sets what
`/work-items:measure-delivery` counts as a deployment, and its one value, the
default, is `merge-to-default-branch`: each commit on the default branch's
first-parent history is a deployment, and one a later commit reverts is a
failed deployment.

`filing_posture` also lives only in the repository file: the team policy for a
scanner's explicit filing argument, such as `/bugs:scan --track`. With
`manual-only`, the default, the scanner files nothing and says why, and a
standing autonomous lane must not file into the tracker. `allowed` lets the
explicit argument file. Neither value makes a bare invocation file. The key
used to live in `docs/conventions/bugs.yaml`; `/bugs:scan` still reads it there
for one release, with a notice, when this file does not set it.

Everything else is project-specific behavior that routes through the consuming
repo's own surfaces: the bound provider in `<home>/work-items.yaml` (including
the optional `tracker.config.role_labels` canonical-role → label remap), its labels
(taxonomy discovery through the adapter), its optional recurring schedule file,
its optional rejected-concept ledger (`docs/out-of-scope/`, checked at intake),
and its own `CLAUDE.md` / rules for write-identity policy (e.g. routing tracker
writes through a bot wrapper) and development workflow. The skills degrade
gracefully when any of these are absent.

### Option details

**`decompose_container_publish`.** The pre-selected offer publishes the Brief as a container item
carrying the binding-resolved container label (default `work-map`), with items as native
sub-items. This key changes the offered default answer and never bypasses approval. It declares no
default so an unset value stays distinguishable from a configured one.

**`work_dispatch_concurrency_cap`.** The cap is the size of one dispatch wave; `/work-items:work`
runs exactly one item per invocation. Give a whole number of rows, since a row is discrete. The key
declares no default, so an unset value stays distinguishable from a configured one, which a
declared default would collapse into a hard cap.

**`lane_instance`.** Follows the loop-lane convention's lane-instance identity rule. Each lane
instance owning its own comment keeps one machine's durable state, such as its adaptive item cap,
from being overwritten by another's.

**`work_loop_frontier_item_cap_ceiling`.** A quota guard: items carrying `capability-tier: frontier`
are bounded by this ceiling instead of the general one.

**`ai_disclaimer`.** The false default is a change on update: lanes always added the disclaimer
before this setting existed, so set it true to keep that behavior.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `decompose_container_publish` | boolean | *(none)* | When true, /work-items:decompose pre-selects the spec-container offer in its approval round for multi-session breakdowns; the approval gate stays mandatory. Unset or false: the plain ask, with a default answer of no. No default is declared, so unset stays distinct from false. |
| `triage_repro_count` | number<br>*min 1* | `2` | Independent reproductions /work-items:triage needs, each with evidence in its comment, before it marks a bug confirmed. Default 2. The repository's docs/conventions/work-items.yaml overrides this per repo. |
| `triage_objection_window_hours` | number<br>*min 0* | `0` | Hours after triage makes an item autonomous-eligible during which the work-loop lane skips it, so a person can object in a reply. 0 (the default) is off. The repository's docs/conventions/work-items.yaml overrides this per repo. |
| `ai_disclaimer` | boolean | `false` | When true, autonomous work-items lanes (triage, work-loop, attend-queue answers, autonomous filing) start each tracker item and comment they create with the AI disclaimer. Default false, so lanes omit it. The repository's docs/conventions/work-items.yaml overrides this per repo. |
| `medium` | string | `"auto"` | Where the /work-items:triage board page and /work-items:morning-brief's status page go. auto (default): a local file; terminal: no page; file: a local file; artifact: a private Artifact; hosted is read as artifact. A team rendered-views file never publishes. |
| `work_dispatch_concurrency_cap` | number<br>*min 1* | *(none)* | Maximum worker rows /work-items:work's autonomous execute step lets /implementation:implement-dispatch run at once in one plan phase, passed as its --wave-cap ceiling. A fractional value is floored. Unset: implement-dispatch's implement_dispatch_wave_cap option, else its internal default. |
| `lane_instance` | string | *(none)* | Writer identity for this machine's work-loop telemetry, the suffix of its telemetry marker, so concurrent lane instances never overwrite each other. Absent: a random id made once and kept in the plugin data dir. Must match ^\[a-z0-9\]\[a-z0-9-\]{0,31}$. It appears verbatim in tracker comments. |
| `lane_app_slug` | string | *(none)* | Slug of the GitHub App whose installation token the work-loop lane runs under, passed as --app-slug to its telemetry upsert so the write identity resolves to <slug>\[bot\]. Needed only under an App token. Absent: the identity resolves from gh api user. Must match ^\[a-z0-9\]\[a-z0-9-\]*$. |
| `work_loop_item_cap_start` | number<br>*min 1* | `2` | Where the work-loop lane's adaptive per-cycle item cap starts. Default 2. The cap ramps up by one after three consecutive clean items (never while a rate-limit warning is latched) and drops by one on any dirty item; enforcement is the loop body's own arithmetic. |
| `work_loop_item_cap_ceiling` | number<br>*min 1* | `3` | Upper bound the work-loop lane's adaptive item cap can ramp to for non-frontier-tier items. Default 3. Frontier-tier items are bounded separately by work_loop_frontier_item_cap_ceiling. |
| `work_loop_item_cap_floor` | number<br>*min 1* | `1` | Lower bound the work-loop lane's adaptive item cap can drop to on dirty items. Default 1. |
| `work_loop_frontier_item_cap_ceiling` | number<br>*min 1* | `2` | Ceiling on the adaptive cap for frontier-capability-tier items in the work-loop lane, which run at concurrency 1. Default 2; keep it at or below work_loop_item_cap_ceiling. The tier is read from the provider-permissioned label only; no label means the general tier (fail-closed). |
| `work_loop_no_progress_threshold` | number<br>*min 1* | `3` | Consecutive no-progress cycles (actionable work in view, no item advanced, no PR opened) before the work-loop lane raises its stall escalation. Default 3. The lane escalates and keeps looping. Idle cycles with nothing actionable neither count nor reset. |
| `work_loop_in_flight_stale_days` | number<br>*min 1* | `14` | Age in days, from the PR's createdAt, past which a candidate's open closing PR (draft or ready) stops being silently excluded and the work-loop lane escalates it to the attended queue. Default 14. The drain report names it; the lane stores no state for it. |

### How to set these

Set the options above for `work-items@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
