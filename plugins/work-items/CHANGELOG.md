# Changelog

All notable changes to the `work-items` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.16.0]

Close the work-item-tracker seam's container read-verb gap (`#498`): the seam reserves `work-map`
containers as a first-class use case but had no way to operate one within scope. The frontier was
repo-global only, its rows dropped parent linkage, an unassigned/unblocked container surfaced as its
own frontier item, and no verb enumerated a container's children — collectively blocking a clean
container-based consumer (surfaced by the `#416` wayfind-routing planning pass). Related but distinct:
`#416` (the wayfind consumer) and `#379` (the Jira adapter, a different backend).

### Added

- **`list-sub-items <parent-id> [--state open|closed|all]` (new seam + adapter verb).** Enumerates a
  container's DIRECT children as full normalized item objects (same `{items:[…]}` envelope as
  `list-items`), each re-parented to the container. Raw enumeration — closed and nested-container
  children are kept, so the "decisions-so-far" closed-children invariant check and sub-map traversal
  both have a seam path. `--state` defaults to `all`. Both adapters implement it: the GitHub adapter
  resolves children through the native `subIssues` link and intersects with `list-items` (its list
  surface omits parent linkage), so its truncation bound is `list-items`' own (`list_items_max`);
  the offline `local-markdown` adapter matches on the stored `parent` frontmatter.
- **`list-frontier --parent <container-id>` (container-scoped frontier).** Scopes the frontier to one
  container's children — core reads `list-sub-items` for that container instead of the repo-global
  `list-items`, then applies the identical filter. Gates on the adapter's `list-sub-items` capability.

### Fixed

- **A container is never its own frontier item (`#498` obs #3).** `list-frontier` now excludes any item
  carrying the container label (`work-map`) unconditionally — global and `--parent`-scoped alike, and
  under `--autonomous` — fixing the correctness wart where an unassigned, unblocked container passed the
  frontier filter and surfaced itself. The container label is a named constant (`WIT_CONTAINER_LABEL`)
  matching the CONTRACT term; per-repo remapping is deferred to the `config.role_labels` convention.

## [0.15.0]

Close the work-items entry-invariant gap where a missing provider binding (`.work-item-tracker.json`)
degraded silently — role labels fell to defaults with no signal, and seam coordination verbs surfaced
a raw mid-flow `exit 3` instead of an actionable message (`#449`). The full remote / no-checkout mode
(shallow-clone or `gh api`-backed codebase reads) stays deferred with a recorded trigger.

### Added

- **Binding presence is a third loud entry invariant (`#449`).** "Shared tracker context" now checks
  the provider binding alongside `jq` and the seam script, but discharges it distinctly: the first two
  have no recovery path and stop; a missing binding is loud and routable, never a silent default and
  never a raw `exit 3`. Seam **coordination** verbs (`create-item`, `get-item`, `claim`, `renew-lease`,
  `reclaim`, `link-blocks`, `add-sub-item`, `list-frontier`, `capabilities`) cannot run unbound, so
  before the first one the skill surfaces a message distinguishing **setup was never run** (→
  `/work-items:setup`) from a **deliberate gh-native
  operating mode** (proceed for provider-mechanic operations only, accepting no race-safe claim/lease).
  Provider-mechanic operations (list/search/close, label/comment edits) run as raw `gh`, never read
  the binding, and proceed unbound. Caveat recorded: the gh-native path presumes a `gh`-backed
  provider — a `local-markdown` target with no binding cannot proceed and stays a hard stop.
  `/work-items:work` gains an explicit binding preflight **before Step 0** — its `reclaim` is the
  lane's first coordination verb, so the check is discharged before it runs rather than surfacing as a
  raw mid-reclaim `exit 3`.

### Changed

- **Silent role-label default becomes a loud warning (`#449`).** When a canonical role resolves to its
  documented default because `.work-item-tracker.json` or its `config.role_labels` entry is absent, the
  skills now warn loudly instead of substituting silently — a repo that remapped `config.role_labels`
  was previously queried under the wrong strings with no signal. Applied at every action-entry
  resolution site that inlines it (`work`, `triage`, `track` — `SKILL.md` summary plus
  `due`/`recheck`/`audit` — and `decompose`) and in the shared invariants (`reference/tracker-seam.md`,
  `reference/label-taxonomy.md`). A present-but-malformed, empty, or non-string configured value
  remains a hard stop, unchanged.

### Deferred

- **A first-class gh-native no-lease claim path for coordination-*dependent* lanes (`/work-items:work`)
  is parked, not built (`#449`).** Making those lanes runnable unbound (assignee-only claim, no lease,
  races are the operator's problem) is claim-safety contract surface — deferred with the same trigger
  as the full remote-repo mode: someone needs unattended coordination-dependent work at scale.

## [0.14.4]

### Fixed

- **`/work-items:work` Step 5 guards against loop-prompts that restate dispatch without the claim (`#581`).**
  Step 5's sequence already put the seam `claim` (assignee + lease) first, but a hand-authored loop-prompt
  standing-rule that restates "dispatch every picked issue to a subagent in its own out-of-tree worktree"
  reads as a complete execution contract on its own and never mentions claiming — so an orchestrator
  following that loop-prompt literally did the worktree isolation and skipped the seam's race-safe claim
  entirely (observed twice on live loop-lane sessions, leaving actively-worked issues unassigned with no
  lease). A prominent guard note at the head of Step 5 now states the claim-before-dispatch invariant the
  skill enforces regardless of loop-prompt wording: worktree isolation is not the collision signal between
  concurrent lanes, the seam claim is, and dispatching a subagent before the claim is held is a defect even
  when the loop-prompt never named the claim step. Documentation/guidance only — no skill-code or seam
  behavior change; eval 1 gains a matching expectation.

## [0.14.3]

### Fixed

- **GitHub adapter `renew-lease` no longer revives an expired lease (`#370`).** `renew-lease` confirmed
  the handle still matched the active (newest non-superseded) lease but never checked liveness, so a
  crashed or delayed holder retaining its handle past `renewed_at + ttl_hours` — with no newer lease
  comment — could PATCH a fresh `renewed_at` and reclaim an item another worker had reasonably treated
  as expired, defeating TTL-based handoff. It now checks `wit_lease_is_live` immediately before
  patching and returns a conflict (exit `7`) for an expired lease instead of reviving it.
- **GitHub adapter `reclaim` unassigns only the expired lease's holder (`#370`).** On the expired-lease,
  no-activity path `reclaim` read all assignees and removed every one, silently unassigning a user
  added manually after the old lease or a concurrent claimer added before the snapshot — in the
  concurrent case leaving that claimer's live lease in place while the frontier treated the item as
  unassigned (two workers on one item). Removal is now scoped to the lease's `holder`, and ownership is
  revalidated immediately before mutating (the lease must still be the active, expired lease) so a
  concurrent claim during the activity-check window aborts the reclaim as a no-op rather than stripping
  the new owner. The shared active-lease selection is extracted to `wit_select_active_lease`
  (`lib/lease.sh`), reused by both verbs.

## [0.14.2]

### Fixed

- **Local-markdown expired lease returns the item to the frontier (`#367`).** For the `local-markdown`
  binding an expired lease still left `assignees` populated, and since `reclaim` is unsupported for
  this offline adapter (no coordination surface to run an activity check over) and `list-frontier`
  always excludes assigned items, any abandoned local claim was permanently absent from selection after
  its TTL expired. `list-items` now projects the effective assignee of an expired-lease item as empty,
  so the core frontier derivation returns it to the frontier — without inventing a new adapter
  capability. The projection is scoped to list/frontier derivation; `get-item` still reports the stored
  assignee verbatim (parity with the GitHub adapter, whose assignee persists until reclaim).
- **Local-markdown claim no longer reports success on a failed assignee write (`#367`).** `claim`
  appended the inline lease marker and then set `assignees` with no return-code check, so a failed
  assignee write (store full or unwritable) was silently ignored and a successful claim JSON was still
  emitted — leaving a live lease marker with an empty `assignees`, which `list-frontier` presents as
  available while later claims conflict on the live lease until it expires. The two writes are now a
  single consistent operation: a failed assignee write rolls the just-appended marker back and fails
  the claim (exit `1`), emitting no success record for a half-applied write.

## [0.14.1]

### Fixed

- **Open-linked-PR filter no longer wrongly drops issues from fenced examples (`#654`).** The GitHub
  adapter's "Open linked PRs" mechanic (`#463`) matched a closing-keyword `jq` regex over the raw
  PR body, so a PR body carrying a fenced `Closes #<N>` example spuriously reported issue `#<N>` as
  having an open closing PR and dropped the still-pickable issue from the `/work-items:work`
  frontier. The mechanic now reads GitHub's own computed close-linkage via the GraphQL
  `Issue.closedByPullRequestsReferences` connection (open-state nodes only), which excludes fenced
  code blocks and HTML comments, needs no word/number-boundary guards, and honors the default-branch
  requirement — retiring the raw-body regex and its partial `gsub` fence-stripper (which recognized
  only exactly-three backtick/tilde fences). Behavior change: an issue whose only `Closes #<N>` is on
  a non-default-base PR now stays pickable, matching GitHub's real auto-close semantics.

## [0.14.0]

Absorb bullets 1–4 of the v4 loop-prompt routing rules into `/work-items:triage` so the skill owns
them instead of a session prompt (`#478`). Bullet 5 stays deferred to `#459` (pointer only); bullet 6
(`wayfind:*` label semantics) is cross-repo label policy noted on `github-iac#176` and untouched here.

### Added

- **Decision-defaulted ready route (`#478`).** "Triage states" now documents three briefed exits —
  delegable, decision-defaulted, human-gated. A single-fork item whose brief carries a well-grounded
  RECOMMENDED answer with only a maintainer-vetoable (reversible) alternative routes to the
  autonomous-eligible role with `status:ready` plus a `Decision defaulted: X — veto before merge`
  comment, instead of falling to human-gated. "Recommend category + state" carries the routing test
  (reversible/maintainer-vetoable → defaulted; genuinely open → human-gated) and "Apply outcome" adds
  the matching row.
- **Cluster-aware routing (`#478`).** "Gather context" adds a cluster-detection cross-reference: when
  several open items share one underlying decision, one representative becomes the decision carrier
  (human-gated, member numbers in its body) and each member links to it via the native `blocked-by`
  edge with a `blocked by #<carrier> decision` comment — no per-member human-gated label. One human
  touch per decision. No new labels.
- **Multi-surface T1 stub (`#478`).** "Apply outcome" adds a lightweight briefing variant: a trivial
  (T1) fix spanning 3+ surfaces gets a one-line `sites + fix pattern` comment in place of a full brief
  and still takes the autonomous-eligible role. The brief durability rule holds — name sites by
  interface / symbol / domain concept, not file paths or line numbers (recommended default:
  symbol-level naming).
- **Severity sub-sort (`#478`).** The priority-label step now records the finding's self-labeled
  severity in the triage comment (`priority set to pX by <rule>; reporter severity: <sev>`) when a
  directive or category rule sets the `priority:` label above it, so implementers can sub-sort within
  a priority band. No new labels.

### Changed

- **Human-gated narrowed (`#478`).** The human-gated briefed exit is reserved for a genuinely open
  decision (open design space, product intent, cross-repo policy) or a capability blocker (external
  access, manual QA), distinguishing it from the new decision-defaulted route.

## [0.13.1]

### Fixed

- **`status: ready` issues with an open linked PR are no longer pickable (`#463`).** `/work-items:work`
  selection now excludes a frontier candidate (tiers 2–3) that already has an open PR targeting it for
  closure, closing the re-pick risk where an issue kept `status: ready` for its entire open-PR window and
  a picker had to hand-cross-check `gh pr list` to avoid starting a duplicate branch. The check routes
  through a new GitHub adapter *Open linked PRs* mechanic (closing-keyword linkage — the same `Closes #N`
  signal `pr-issue-linkage` enforces — is authoritative; an intentional `Refs #N` opt-out does not
  exclude), and fails open when the bound provider exposes no PR host (offline `local-markdown`). This
  retires the interim in-flight heuristic that lived in the execute-step staleness pre-check. The durable
  seam-level in-review state is deferred to the tracker-seam layer (`#416`/`#498`), not built here.

## [0.13.0]

Absorb the v4 loop-prompt execution rules into `/work-items:work` so the execute step owns them
instead of a session prompt, delegating anything a sibling skill already owns rather than restating it.

### Added

- **Orchestrator-dispatch is the documented default for autonomous execution (`#451`).** The execute
  step's generic "follow the project's development workflow" deference now states the default posture:
  pick and claim, then dispatch a scope-fenced implementation subagent that edits source in its own
  out-of-tree worktree — the orchestrator never edits source. Dispatch *mechanics* are chained to
  `/implementation:implement-dispatch` (not re-described); worktree lifecycle stays with
  `/source-control:worktree`; the interactive all-inline path remains `/implementation:implement`.
  The autonomous dispatch handoff (branch/worktree provisioning before the dispatch preflight and
  orchestrator-owned PR creation) is not yet guaranteed end-to-end — deferred to `#572`.
- **The dispatch brief carries the PR contract forward (`#462`).** The brief relays what
  `/source-control:pull-request` will require at PR time — that skill still owns the PR body shape,
  `Closes #N` injection, and merge style — enumerating the version-bump, CHANGELOG, attribution-trailer
  plus session link, and `## Related` obligations so a worker knows them up front, not via red CI.
- **Post-green review pass with work-item linkage.** After CI green, one review pass fixes branch-owned
  findings via the owning subagent; the fetch → validate → classify → reply → resolve loop stays owned
  by `/source-control:pull-request`. A VALID-but-deferred finding now requires a follow-up issue filed
  via `/work-items:track add`, cited in the reply and in `## Related`, before it can be resolved. The PR
  then hands off to `/source-control:babysit-prs`.
- **High-blast-radius pre-PR diff gate.** The orchestrator does a full-diff read before opening a PR
  when the diff touches skill frontmatter descriptions or trigger keywords, cross-plugin contracts, or
  hooks — complementing the worker scope-fence with an orchestrator read of what actually changed.
- **Concurrency and batch caps as `userConfig`.** New `work_dispatch_concurrency_cap` (default mirrors
  `/implementation:implement-dispatch`'s 3–5 wave cap) and `work_cycle_batch_cap` scalars; the execute
  step resolves them from config with no hardcoded literal. Enforcement is not yet wired — these are the
  *intended* values (implement-dispatch still applies its own internal cap and no consumer reads the batch
  cap), with threading into the delegated dispatch and driving loop tracked in `#573`. A batch cap bounds
  one CYCLE, never the loop
  — cap-reached or frontier-drained ends the cycle only, not autonomous operation (loop wakeup and delay
  stay owned by `/loop`). Same-plugin serialization carries an interim awareness note pending `#464`.
- **Explicit never-merge boundary.** The skill states that `work`'s lane ends at PR creation and
  handoff; merging is the babysit lane or a human, never `work`.

### Changed

- **Selection skips a frontier item that already has an open PR (interim, retire on `#463`).** The
  staleness pre-check advances past an in-flight item rather than starting a duplicate branch, until the
  durable in-progress marker lands and the frontier excludes in-flight items itself.

## [0.12.3]

### Fixed

- **Triage's step-2 wait-gate no longer contradicts its own autonomous mode.** The "Recommend
  category + state" step ended with a flat "Wait for the user's direction before mutating anything,"
  while the AI disclaimer section presupposed the opposite — autonomous/agent sessions that mutate
  without a human turn. No branch selected between them, so an operator following step 2 could not triage
  autonomously and an autonomous lane necessarily violated step 2. The gate is now an explicit
  two-branch direction gate: interactive sessions (a human present, no standing lane rules) keep the
  wait-gate; autonomous `/loop` / `/schedule` AFK lanes treat their standing rules as the direction
  the gate requires and proceed without a human turn (the mode the AI disclaimer already anticipates),
  so the gate is satisfied by the lane's mandate rather than silently ignored.

## [0.12.2]

### Fixed

- **Triage outcomes now clear the raw-intake marker.** The `triage` skill's "Apply outcome" step
  listed the labels each outcome adds but never said to remove `status:needs-triage`, so applying an
  outcome stacked `status:ready` and the role label on top of the raw marker. The attention view
  re-selects any open item still carrying the marker, so triaged items re-triaged every cycle
  (silent-loop-kill class). Step 5 now states that every outcome is a transition off raw that
  replaces the marker rather than adding to it, and a closing invariant forbids a raw marker
  alongside a briefed/ready or role label on an open item.

## [0.12.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/prototype:pressure-test`); behavior unchanged.

## [0.12.0]

Bundle the work-item-tracker seam into the plugin so installing it delivers the engine and the
shipped adapters — no per-repo vendoring. Executes shape A of the tracker-seam distribution decision.

### Added

- **The seam ships with the plugin.** The dispatcher, `lib/`, `CONTRACT.md`, the `github` and
  `local-markdown` adapters, and the conformance suite now live under
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/`. A consuming repo gets the seam by installing the
  plugin; it no longer has to vendor `tools/work-item-tracker/` itself.
- **Two-rule resolution.** Seam code resolves **plugin-dir canonical, project-root fallback**;
  adapters resolve **consumer-local-first, plugin-bundled fallback** (first match wins). A repo can
  add a provider the plugin does not ship, or shadow a bundled adapter with a local copy it owns, at
  `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/` — without forking the plugin
  (CONTRACT.md "Adapter resolution").
- **Provider binding in setup.** `/work-items:setup apply` now seeds `.work-item-tracker.json`
  (provider + non-secret config) as the once-per-repo binding step, run first — ahead of the
  recurring-schedule and role-label passes; `/work-items:setup check` verifies the binding's presence
  and validity read-only. The binding step extends the uniform check/apply contract [0.11.0]
  established rather than adding a second setup surface. The seam still hard-errors (exit 3) at call
  time when no binding is present.

### Changed

- **Skill seam invocations resolve the bundled dispatcher first.** Each executable snippet resolves
  `"$TRACKER"` plugin-dir-canonical with a project-root fallback, then invokes it; doc citations point
  at `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/...`.
- **Adapter operations reference and CONTRACT are provider-neutral.** The GitHub adapter reference and
  the contract no longer cite a specific consuming repo's convention docs or bot-auth wrapper; writes
  optionally route through a bot wrapper when the consuming repo provides one, otherwise bare `gh`.
- **Adapters hard-fail on a missing shared seam lib.** `github` and `local-markdown` `common.sh`
  verify each required `lib/` helper exists before sourcing and exit 3 with a diagnostic if absent, so
  a consumer-local adapter shadow that cannot resolve the bundled `lib/` fails loudly instead of
  silently emitting a malformed (empty-id) record.

## [0.11.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects read-only the tracked
  `.github/recurring-schedule.json` (presence — absent is INFO, since `due` / `recheck` / `work` degrade
  gracefully — JSON validity, and the unique `id`/`title` reconciliation keys), the `jq` and
  tracker-seam entry gates (probed via `reference/tracker-seam.md`, not restated), and the
  recurring-maintenance role label, reporting a PASS/FAIL/INFO table; `apply` runs the
  interview-seed-reconcile flow and the optional role→label remap, then re-runs `check` to verify. The
  schedule shape, reconciliation logic, and role-label invariants are unchanged; the read-only
  inspection path and the `check | apply` argument-hint are new.

## [0.10.0]

### Changed

- **Runtime prerequisites declared and classified** (prerequisite-visibility
  wave). README Requirements now name Bash + `jq` (Git Bash on native
  Windows, where `jq` is a separate install) and classify `jq` as required
  for correctness — stop with the install remediation, never improvise a
  parse. The tracker-seam reference gains an explicit entry-point presence
  check for the seam script with a remediation pointer
  (`tools/work-item-tracker/CONTRACT.md`, `/work-items:setup`) instead of
  failing on the first verb.

## [0.9.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` names the
  tracker as the contract's cross-lane index — tickets point, never store primary artifacts;
  `/work-items:decompose` ticket provenance now cites the PR carrying the source plan instead of
  the contract-slice path, which is pruned before merge and would dangle. Pre-PR publishes record
  slug + phase (a label, not a path) and backfill the PR reference as a comment once it opens.

## [0.8.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

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
