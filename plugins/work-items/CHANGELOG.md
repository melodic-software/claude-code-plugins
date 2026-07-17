# Changelog

All notable changes to the `work-items` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` names the
  tracker as the contract's cross-lane index — tickets point, never store primary artifacts;
  `/work-items:decompose` ticket provenance now cites the PR carrying the source plan instead of
  the contract-slice path, which is pruned before merge and would dangle.

## [0.8.0]

### Changed (breaking)

- **Skill renamed: `scan` → `scan-todos`.** `/work-items:scan` no longer exists; invoke
  `/work-items:scan-todos`. Under the `work-items` namespace the bare verb read as scanning
  tracker items; the skill sweeps the codebase's source comments for TODO/FIXME/HACK/XXX
  markers, so the name now states its object. No behavior change; no alias or renames-map
  entry — clean break per the marketplace's settling-phase rename policy.

## [0.7.0]

Split the single `work-items` action-router skill into five focused skills. The capability set is
unchanged — the same taxonomy, seam, canonical-role remap, and recurring-schedule behavior — only
decomposed so each surface is invoked directly. The separate `setup` skill is unchanged.

### Changed (breaking)

- **One skill → five skills.** The `work-items` skill (an action router over 13 actions) is
  replaced by five skills. The nine backlog-CRUD verbs stay behind a sub-action router in `track`;
  the four multi-step surfaces each become a standalone skill. Invocation mapping:

  | Old | New |
  |-----|-----|
  | `/work-items:work-items` (bare — stats dashboard) | `/work-items:track` (default = stats dashboard) |
  | `/work-items:work-items {stats\|list\|add\|start\|done\|due\|recheck\|search\|audit}` | `/work-items:track <action>` |
  | `/work-items:work-items triage` | `/work-items:triage` |
  | `/work-items:work-items work` | `/work-items:work` |
  | `/work-items:work-items decompose` | `/work-items:decompose` |
  | `/work-items:work-items scan` | `/work-items:scan` |

- **Shared context lifted to the plugin level.** The tracker seam, operation routing, label
  taxonomy, canonical-role resolution, recurring-schedule note, integration points, and gotchas —
  previously repeated in the router body — now live once in `reference/tracker-seam.md`, and each
  skill references it via `${CLAUDE_PLUGIN_ROOT}`. The `label-taxonomy.md` and `agent-brief.md`
  references and the `checklist.md` template moved from the skill directory to the plugin root
  (`${CLAUDE_PLUGIN_ROOT}/reference/…`, `${CLAUDE_PLUGIN_ROOT}/templates/…`) so all five skills
  share one copy; `topic-docs.md` was already there.

### Added

- **Per-skill eval coverage.** Each new skill ships its own `evals/evals.json`: `track` (empty-args
  stats default + the remapped-role due/recheck/audit cases), `work` (auto-select-and-claim + the
  remapped-role frontier case), `triage` (PR-as-item, verify-before-interview, never-re-triage
  decompose output), `decompose` (vertical-slice HITL/AFK dependency ordering), and `scan`
  (single-pass sweep + marker classification). The `work` case's workflow-chain example was updated
  to the current cross-plugin skill names.

## [0.6.0]

Raw-intake triage, canonical role labels, and the rejected-concept ledger check.

### Added

- **Canonical-role → label mapping.** The skills now speak three canonical roles —
  `autonomous-eligible`, `human-gated`, `recurring-maintenance` — and resolve each repo-actual
  label string from the tracker binding (`.work-item-tracker.json`, `config.role_labels`).
  Defaults are the previous literals (`agent-ready` / `needs-human` / `recurring`), so existing
  consumers need zero migration. The role table and binding shape live in
  `reference/label-taxonomy.md` "Canonical roles"; `/work-items:setup` offers the remap interview
  (with an existence check on the target label and a warning that `human-gated` is shared with the
  seam's `list-frontier --autonomous` exclusion).
- **Rejected-concept ledger check at intake.** When the consuming repo keeps a ledger
  (`docs/out-of-scope/`, one file per concept), `add` and `triage` match incoming requests against
  it by concept similarity and answer from the ledger — appending the request to the concept
  file's "Prior requests" log — instead of re-litigating a prior rejection. `triage` records a
  newly rejected enhancement there and links it from the closing comment; already-implemented
  closes are never ledgered. Degrades gracefully: no `docs/out-of-scope/`, no check.
- **Triage eval coverage** — PR-as-item routing, verify-before-interview ordering, and the
  never-re-triage-decompose-output exclusion.

### Changed

- **`triage` reworked as the raw-intake state machine.** Triage now covers items the team did not
  author — bug reports, incoming feature requests, and unsolicited PRs — through
  raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and
  close. An unsolicited PR enters the same intake as an issue: its diff is an attachment to
  evaluate, never an obligation to merge. Verification (reproduce the bug / confirm the diff does
  what it claims) precedes any interview, and a briefed outcome follows the agent-brief
  durability-over-precision rule (behavioral contracts, no file paths or line numbers). Items
  published by `decompose` are born triaged and never re-enter the flow.
- **Re-read-before-write + append-only discipline** on multi-turn shared artifacts (the recurring
  schedule, the checklist ledger, out-of-scope concept files, the tracker binding): re-read from
  disk immediately before writing and append/merge rather than rewriting from a stale in-context
  copy.

## [0.5.0]

Adopt the marketplace topic-docs convention (`docs/conventions/topic-docs/`, contract v1.0.0).

### Added

- **`reference/topic-docs.md`** — the plugin's binding to the contract: which paths the skill reads
  and writes per tier (the `work-items-checklist.md` ledger and ad-hoc notes are memory-tier under
  `.work/<slug>/`; tracker projections go through the seam, never files), the slug spec and
  self-ignore guard, and the two-location plan/PRD lookup.

### Changed

- **`decompose` default source moved to the contract tier.** The topic's `PLAN.md` / `PRD.md` now
  resolve via a two-location lookup: `docs/topics/<slug>/` (contract slice on the task branch,
  default) → `.work/<slug>/` (`contract_tier: local`). Previously the default was `.work/<slug>/`,
  which the convention classifies as memory tier — plans are contract documents. The prior
  `.claude/notes/<slug>/` location is retired outright — no compatibility layer; move residual
  content manually.
- The checklist emit path (`.work/<slug>/work-items-checklist.md`) is now governed by the binding:
  `<slug>` derives per the shared slug spec and the session's first memory-tier write verifies the
  resolved memory root's self-ignore guard (a `.gitignore` containing `*`, created and announced
  when absent).

## [0.3.0]

### Added

- **Re-runnable `setup` skill for the recurring-schedule seam.** `/work-items:setup` interviews the
  consumer, infers candidate recurring items from the repo layout (dependency manifests, lint config,
  CI workflows, security surfaces), and writes the tracked `.github/recurring-schedule.json` — the
  bulk / initial-config path complementing the per-item `add --recurring`. Idempotent: re-run to
  reconfigure. Seeds new rows with today-based dates but never advances an existing row's cadence
  clock (that stays `recheck`'s job), ensures the load-bearing `recurring` label exists, guards `id`
  and `title` uniqueness (both reconciliation keys), and reconciles a renamed row's still-open
  `[Maintenance]` item.

### Fixed

- `due` and `work` now match a due recurring item's tracker item by the **full** `[Maintenance]
  {title}`, exact — never a bare prefix or substring — so a shorter title cannot spuriously match a
  longer item's record.

## [0.2.0]

Re-plumbed onto the provider-neutral work-item-tracker seam. The skill is now backend-agnostic; GitHub
is the bound adapter today rather than a hardcoded dependency.

### Changed (breaking)

- **Provider-neutral over the tracker seam.** Every tracker operation routes through the
  work-item-tracker seam — the skill calls `tools/work-item-tracker/work-item-tracker.sh <verb>` and the
  bound provider adapter executes it (contract: `tools/work-item-tracker/CONTRACT.md`). The skill core
  inlines **no** provider commands: coordination (create, claim, renew/reclaim lease, dependency links,
  sub-items, frontier selection, single-item fetch) uses seam verbs, and provider mechanics (filtered
  listing, search, aggregation, close, label/comment edits) reference the bound adapter's operations
  doc. Previously the skill called `gh` directly throughout.
- **Claim protocol is now assignee + lease, race-safe at the seam.** The label-based
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim dance (`status:considering` / `status:claimed`) is retired.
  Claiming assigns the item and writes a lease comment; races are resolved by lease-comment identity,
  and a session-start `reclaim` runs idempotently to recover crashed sessions' stale leases. The claim
  identity is always the authenticated session user, never a shared bot.
- **New consumer requirement.** The consuming repo provides the seam at `tools/work-item-tracker/` and
  binds its active provider in `.work-item-tracker.json`. The skill no longer shells out to `gh` on its
  own; the GitHub adapter behind the seam does.

### Changed

- Backend-neutral vocabulary throughout — "work item" rather than "GitHub issue"; the description and
  action docs read against any bound provider.
- Removed the skill's `gh`-scoped `allowed-tools` and the inline `gh`-based pre-computed dashboard
  block; the dashboard now derives through the seam and adapter.
- The agent-brief template ships at `reference/agent-brief.md`.

## [0.1.0]

- Initial release: a GitHub-Issues work-item tracker skill — `stats`, `list`, `add`, `work`, `start`,
  `done`, `due`, `recheck`, `search`, `scan`, `audit`, `decompose`, `triage` — with a `gh`-backed
  hold&nbsp;→&nbsp;verify&nbsp;→&nbsp;claim multi-agent claim protocol.
