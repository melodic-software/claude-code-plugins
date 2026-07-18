# Shared tracker context — every work-items skill

The five work-items skills (`track`, `triage`, `work`, `decompose`, `scan-todos`) share one tracker
seam, one label taxonomy, one canonical-role remap, and one topic-docs binding. Those invariants
live here so each skill states them once by reference rather than restating them. Read this document
(and the references it links) at the start of any work-items skill invocation.

## Scope

These skills manage **development work items** — maintenance tasks, feature requests, bug reports,
recurring audits, and housekeeping — through a centralized, concurrent-safe work-item tracker.

## Provider-neutral over the seam

Every tracker operation goes through the work-item-tracker seam — the skill calls
`tools/work-item-tracker/work-item-tracker.sh <verb>` and the bound provider adapter executes it
(contract: `tools/work-item-tracker/CONTRACT.md`). Resolve the seam path from the project root so
invocations work from any subdirectory —
`"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" <verb>`;
the executable snippets in each action use that rooted form. The seam is required for correctness:
before the first verb of an invocation, check the script exists at that path — absent, stop and
surface the remediation (this repo has not provisioned the consumer-provided seam; it must be
copied in from a repository that carries it, together with its `CONTRACT.md` and the bound
adapter — `/work-items:setup` configures the recurring schedule and label remaps but does NOT
create the seam) instead of improvising provider commands. The repo's active provider is bound in
`.work-item-tracker.json`. Coordination — create, claim (assignee + lease), lease renew/reclaim,
dependency links, sub-items, frontier selection, single-item fetch — uses seam verbs directly.
Operations without a core verb (listing with arbitrary filters, search, aggregation, close,
label/comment edits) are provider-specific; for the bound GitHub adapter their mechanics live in
`tools/work-item-tracker/adapters/github/README.md`. The skill core stays provider-portable and
inlines no provider commands.

## Operation routing

The skill core carries no provider commands. Every action routes its tracker operations one of two
ways:

| Kind | Where |
|------|-------|
| **Coordination** — create, claim (assignee + lease), renew/reclaim lease, dependency links, sub-items, frontier selection, single-item fetch | Seam verbs: `tools/work-item-tracker/work-item-tracker.sh <verb>` — contract in `tools/work-item-tracker/CONTRACT.md` |
| **Provider mechanics** — list with filters, search, aggregate/count, close, label/assignee edits, comments | The bound adapter's operations reference (GitHub: `tools/work-item-tracker/adapters/github/README.md`) |

Coordination claims are race-safe at the seam (assignee + lease comment; `tools/work-item-tracker/CONTRACT.md` "Lease protocol") — the retired hold→verify→claim label dance is gone. Reads are non-mutating; writes route through the adapter's identity policy.

## Default = fix, not file

Do NOT reflexively suggest `/work-items:track add` or `/work-items:scan-todos` for small / medium drift
discovered while working. Boy Scout scope (cosmetic, stale counts, broken links, single-line
corrections, one-paragraph clarifications) belongs in the current change, not the tracker. File NEW
items only when the work is genuinely orthogonal to the current session, large enough to need its
own `/planning:plan` pass, or needs research the current session isn't positioned to do. Auto-suggesting
`add` for fixable scope is the failure mode this rule prevents. When in doubt, fix in-place and
surface what was fixed in the commit message / PR description.

## Label taxonomy

Work items are classified along a prefix-axis grammar — UNIVERSAL axes (work in any repo) plus
REPO-SPECIFIC axes carrying this repo's concrete values. Members are **not** snapshotted here:
discover them live through the bound tracker adapter. When the consuming repository declares a
label-as-code source of truth, that system owns writes and this skill remains read-only. The **type
axis may be a native GitHub Issue Type** (`Bug`/`Feature`/`Task`) when the repository exposes it;
otherwise use the repository's live `type:` labels. Three meta labels are **canonical roles** —
`autonomous-eligible`, `human-gated`, `recurring-maintenance` — whose repo-actual strings resolve
from the tracker binding's `config.role_labels` (defaults `agent-ready` / `needs-human` /
`recurring`; see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md)
"Canonical roles"). The grammar and citations live in
[`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md).

| Axis | Mechanism | Scope | What it encodes |
|------|-----------|-------|-----------------|
| Type | native Issue Type (org) · `type:` label (personal) | universal | `Bug` / `Feature` / `Task` — the kind of issue; commit-type granularity stays at the commit layer |
| Priority | `priority:` | universal | urgency — members from the live set |
| Status | `status:` | universal | exception + gate flags only (`needs-info`, `needs-decision`, `ready`, `needs-triage`); claim = assignee + lease, blocked = native edge (neither is a label) |
| Meta | (none) | universal | `automated`, `good-first-issue`, `migrated`, `stale`, plus the canonical-role labels (defaults `agent-ready`, `needs-human`, `recurring`) |
| Area | `area:` | repo-specific | the consuming repo's architecture surface — see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) |
| Category | `category:` | repo-specific | the consuming repo's domain categorization — see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) |
| Ecosystem | `ecosystem:` | repo-specific | the consuming repo's language/toolchain mix — see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) |
| Cadence | `cadence:` | repo-specific | e.g. `cadence:weekly`, `cadence:monthly` — members from the live set |

## Role-label resolution is an action-entry invariant

At the start of every action that queries, creates, or filters items by a canonical role, read
`.work-item-tracker.json` and resolve each role the action uses from `config.role_labels`; an absent
file or absent entry uses the documented default. Keep those resolved strings for that invocation and
use them in every adapter query and core-side label comparison. Never put a default literal such as
`recurring` into a provider query after the role has been remapped. A present binding with invalid
JSON, a non-string role value, or an empty role value is a configuration error: stop and report it
rather than silently querying the default.

## Recurring schedule

Recurring items are defined in `.github/recurring-schedule.json` and created as items by the
consuming repo's recurring-issues automation when they come due. The `/work-items:track recheck`
action updates this schedule after completing a periodic check.

## Topic-docs binding

Memory-tier writes (checklists, ad-hoc notes) and the tier-selected plan/PRD lookup resolve through
this plugin's topic-docs binding — [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).
Derive `<slug>` per its slug spec and, on the session's first memory-tier write, verify the resolved
memory root's self-ignore guard (a `.gitignore` containing `*`, created and announced when absent).

## Integration points

### With `/workflow`

The project's development workflow — a `/workflow` skill, a CLAUDE.md workflow section, or team
convention — applies to every item worked via `/work-items:work`; the `work` skill chains its full
step sequence.

### With `/retro`

The retrospective skill's Phase 3 surfaces "Issue candidates" — deferred research, discovered gaps,
recurring recheck updates. Approved items use `/work-items:track add`. Mid-session learnings can be
captured with `/retro codify`.

### With `/pull-request`

Branch name `<type>/<N>-<short-slug>` (proposed by `/work-items:track start` / `/work-items:work`)
carries the item number forward. `/pull-request create` parses the branch name and injects the
closing keyword into the PR body; the pre-create gate verifies the keyword (or an opt-out marker) is
present before creating the PR. Closing-keyword shape and PR body shape are owned by `/pull-request`.

`/work-items:track done --pr <N>` is the belt-and-suspenders path for manual PR flows where
`/pull-request create` was not used: it verifies keyword presence on the unmerged PR body or falls
back to closing the item when the PR has already merged (mechanics: the GitHub adapter README "PR
closing-keyword mechanics").

### With autonomous agents

Items carrying the autonomous-eligible role label (default `agent-ready`) with no assignee are
available for autonomous agent pickup. The `work` skill's seam claim (assignee + lease) prevents
concurrent agent collisions. The `track audit` action detects stale claims from crashed/abandoned
agent sessions.

### End-of-session check

At end of session, alongside `/retro`, check `/work-items:track due` to see if any recurring items
need attention.

## Gotchas

Skill-behavior failure patterns. Add to this section when new gotchas are discovered.
Provider-mechanic gotchas (Windows `\r`, search-qualifier syntax, the `gh` 30-row default limit,
`--add-label` vs `--label`, `--reason` values, rate limits, Issue-Forms auto-labeling) live in the
bound adapter's operations reference — for GitHub, `tools/work-item-tracker/adapters/github/README.md`
"Gotchas".

- **Claim concurrency is the seam's job.** Claiming is race-safe at the seam (assignee + lease
  comment, same-identity aware) — `tools/work-item-tracker/CONTRACT.md` "Lease protocol". Reclaim
  runs idempotently at session start (`work` / `track start`). Do not hand-roll a label-based hold
  protocol.
- **Recurring schedule is in `.github/`, not the skill directory.** The schedule file is
  `.github/recurring-schedule.json`. It's version-controlled and shared. The consuming repo's
  recurring-issues automation reads it; the `/work-items:track recheck` action updates it.
- **Multi-turn shared artifacts: re-read from disk, then append.** Immediately before writing any
  shared artifact that outlives a single turn (the recurring schedule, the checklist ledger, an
  out-of-scope concept file), re-read it from disk — another session may have written since it was
  last in context — and append or merge into what's there rather than rewriting the whole file from
  memory.

## What these skills do NOT do

- Inline provider (`gh`) commands — coordination goes through the seam, provider mechanics through
  the bound adapter reference.
- Own the label taxonomy content — that is
  [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md)
  (universal + repo-specific groups).
- Bind the provider — the active provider lives in `.work-item-tracker.json`, not here.
