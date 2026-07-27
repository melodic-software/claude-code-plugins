---
name: work
description: "Auto-select one development work item from the tracker frontier and execute it end-to-end through the project's development workflow. Use when: 'pick work', 'work the next item', 'what should I work on next', 'grab the next work item', 'auto-select a work item', 'work an item', 'do the next thing', 'start on the backlog'. Selects exactly ONE item by priority tiers (due recurring, guardrails, highest-impact, then not-yet-due recurring), claims it race-safe via the seam (assignee + lease), then runs the full workflow. Sibling skills: /work-items:track (backlog CRUD — add, start, done, list, stats, search, due, recheck, audit), /work-items:triage (raw intake), /work-items:decompose (plan → tickets), /work-items:scan-todos (TODO sweep)."
argument-hint: "(no arguments — auto-selects and claims one frontier item)"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: anytime
  cheatsheet-summary: Auto-select one work item and execute it end-to-end
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Coordination goes through the
seam (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh <verb>`); provider mechanics route through the
bound adapter's operations reference; the core inlines no provider commands.

## Purpose

Auto-select one work item and execute it, following the project's development workflow.

## Emit checklist

This is the most common multi-step path. Copy the "Action: work" section of
[`${CLAUDE_PLUGIN_ROOT}/templates/checklist.md`](${CLAUDE_PLUGIN_ROOT}/templates/checklist.md) into
`<memory_dir>/<slug>/work-items-checklist.md` (default `.work/`) — a memory-tier write under this
plugin's topic-docs binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)):
derive `<slug>` per its slug spec and, on the session's first memory-tier write, verify the resolved
memory root's self-ignore guard (a `.gitignore` containing `*`, created and announced when absent).
Tick each step as completed.

## Permission preflight (before Step 0)

The **first** loop-start action — ahead of the binding preflight — surfaces any missing permission
grant or untrusted worktree root **once, up front**, so the unattended lane never rediscovers it as
a mid-cycle prompt. Pass the out-of-tree worktree root this lane is configured to dispatch into
(the `/source-control:worktree` layout); omit `--worktree-root` only for a fully inline run.

```bash
PREFLIGHT="${CLAUDE_PLUGIN_ROOT}/skills/work/scripts/preflight.sh"
"$PREFLIGHT" --worktree-root "<configured-worktree-root>"
```

The check is **report-only** and always exits `0`. On any `GAP`, surface the exact remediation once
and continue per this lane's report-only posture — the fix is **operator-side** (the standards
permission floor and the local `additionalDirectories` seam) and is **never self-applied**: the
classifier blocks an agent broadening its own `permissions.allow`, and a plugin `settings.json`
grant is inert. Never retry a permission denial into broader grants. The full contract, remediation,
and the `/source-control:babysit-prs` applicability note live in
[`${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md`](${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md).

## Binding preflight (before Step 0)

Step 0's `reclaim` is this lane's **first seam coordination verb**, so the binding-presence entry
invariant ([`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
"Shared tracker context") is discharged **here, before Step 0 runs** — never left to surface as a raw
`exit 3` mid-reclaim. If `.work-item-tracker.json` does not resolve, surface the actionable choice
before attempting `reclaim`: **(1) setup was never run** → run `/work-items:setup` to bind the
provider; **(2) a deliberate gh-native operating mode** → this lane is coordination-*dependent* (Step
0 `reclaim`, `list-frontier`, and the Step 5 `claim` are all seam verbs that need the binding), so an
unbound run cannot acquire a race-safe claim/lease. Do NOT silently skip the claim and dispatch anyway
(claim-before-dispatch is a Step 5 invariant): surface that the lane is unbound and stop for the
remediation. A first-class gh-native no-lease claim path for this lane is a parked decision, not yet a
supported mode. A `local-markdown` target with no binding cannot proceed at all.

## Step 0: Session-start reclaim (idempotent)

Before selecting, clear stale claims left by crashed or abandoned sessions (an idempotent entry step). Enumerate currently-assigned items (adapter: "List items", assigned filter — the rows carry `number`), resolve each `number` to a fully-qualified id (adapter: "Resolve item ID"; `reclaim` rejects a bare number), and run the seam `reclaim` verb on each id — idempotent; outcome + activity-check semantics per `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol".

```bash
TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
[[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
"$TRACKER" reclaim "<id>"
```

Exit `6` (capability-unsupported, CONTRACT.md "Exit codes") means the bound provider declares `reclaim: false` (e.g. `local-markdown`, whose `claim` already race-checks the lease pre-write — CONTRACT.md "Adapter contract") — not an error; skip this step entirely (assigned-item enumeration + per-id reclaim) and proceed to Selection Priority.

**Classifier denial of the reclaim call (distinct from any script exit code).** An auto-mode risk
classifier can refuse the `reclaim` Bash tool call itself, before the script runs — no exit code is
produced (CONTRACT.md "Exit codes"). This is a known, observed op-side condition (work-loop
self-observation #1381: the sibling `claim` verb on the same script, invoked moments later, was NOT
blocked — the asymmetry could not be explained by `permissions.allow`/`deny` coverage, since neither
verb carries an explicit rule in the fleet's permission floor at the time of writing). Do not retry
the denied call, do not treat it as a hard failure, and do not attempt to self-widen permissions to
work around it (the classifier blocks an agent broadening its own grants — see
`${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md` "Why a preflight, not a fixer"). Report
it once for the cycle (not once per id), skip this step entirely, and proceed to Selection
Priority — the same posture as
exit `6`. Stale leases from crashed/abandoned sessions will accumulate under this condition until an
operator resolves the classifier gap; that degradation is expected and non-blocking, not a reason to
stop the lane.

## Selection Priority

`/work-items:work` evaluates these tiers top-down, only falling through to the next tier when the current one yields no candidates. Tiers flagged last-resort are skipped if any prior tier already yielded a candidate.

1. **Due recurring items** — `recurring-schedule`, where `next_due <= today`, sorted by `next_due`. Schedule commitments take precedence over category flags; picking a recurring item early shifts its subsequent cadence and undermines the recurrence guarantee.

2. **Non-recurring guardrails items** — the frontier (open ∧ unblocked ∧ unassigned) filtered to `area: guardrails` (when the repo defines that area), non-recurring. Force multipliers — each one completed makes ALL future autonomous work more reliable. Within this tier, prefer: enforcement mechanisms (CI/CD gates, architecture tests, hooks) > tool validation > research/planning.

3. **Highest-impact non-recurring unassigned items** — the remaining frontier, non-recurring, oldest-first. Select based on: items that unblock others, items in smaller categories, shorter well-scoped items over sprawling research epics.

4. **Recurring items not yet due** (last-resort) — `recurring-schedule`, where `next_due > today`, sorted by `next_due`. LAST RESORT only, when tiers 1–3 are empty. Picking a recurring item before its `next_due` shifts the cadence forward — avoid unless nothing else is available. Prefer items closest to `next_due` (least cadence disruption).

## Workflow

### Role-label preflight

Before any tracker read, resolve `recurring-maintenance` from `.work-item-tracker.json`
`config.role_labels`, using `recurring` only when the file or entry is absent — and warn loudly when
it defaults for that reason (surface it, never silent). Stop on a malformed, empty, or non-string
configured value. Use the resolved string for every recurring/non-recurring
filter and every adapter query in this action; do not compare labels against the default literal after
a remap.

### Step 1: Find candidates

For each tier, emit the corresponding query:

- **Recurring tiers (1, 4):** filter the schedule locally:

  ```bash
  SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
  if [[ -f "$SCHEDULE" ]]; then
    jq --arg today "$(date +%Y-%m-%d)" \
      '[.items[] | select(.next_due != null and .next_due <where_expr> $today)] | sort_by(.<sort-by>)' "$SCHEDULE"
  fi
  ```

  where `<where_expr>` is `<=` (current/overdue) or `>` (not-yet-due) per the tier's `where` field.

- **Frontier tiers (2, 3):** the seam derives the frontier (open ∧ `blocked_by_count == 0` ∧ unassigned); filter its output by the tier's category/recurring criteria core-side:

  ```bash
  TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
  [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
  "$TRACKER" list-frontier --autonomous
  ```

  `--autonomous` additionally excludes items carrying the human-gated role label (`needs-human` by default — [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles"). Tier 2 keeps only `area: guardrails` items that do not carry the resolved recurring-maintenance label; tier 3 keeps the rest of that non-recurring set. The normalized frontier model omits `createdAt`, so apply tier 3's **oldest-first** ordering by sorting the candidates on `createdAt` from the adapter "List items" projection (over the frontier numbers) before picking the top one — pass an explicit `--limit` covering the whole frontier on that projection so the default truncation can't hide an older candidate outside the first page and defeat the oldest-first pick (page per the adapter "List items" note if the frontier exceeds the max page size). Provider search syntax never leaves the adapter — the label filter runs over the labels `list-frontier` already returns.

**Exclude in-flight frontier candidates (open linked PR).** A frontier candidate (tiers 2–3) that already has an open PR targeting it for closure is work already in flight — drop it from the pickable set so it is not re-picked. For each surviving frontier number, query the bound adapter's *open linked PRs* operation (GitHub: [`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md) "Open linked PRs") and exclude the number when it reports an open PR closing that item. The **closing-keyword linkage** is the authoritative signal — the same `Closes #N` / native-closing-keyword linkage `pr-issue-linkage` enforces (owned by `/source-control:pull-request`), so an intentional `Refs #N` opt-out does not exclude its issue. Provider search syntax never leaves the adapter — this filter reads only the open-closing-PR boolean the adapter returns per number. **Fail closed when the in-flight check itself fails:** a query that errors (the adapter operation exits non-zero and returns no boolean — expired token, rate limit, network error) is *not* a `false`; exclude the number this cycle rather than treating an unconfirmed check as "no open PR", which would re-dispatch precisely when in-flight state could not be verified. **Fail open when the bound provider exposes no PR host:** the offline `local-markdown` binding is never a coordination surface and touches no network tool ([`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md) "local-markdown adapter"), so when no PR-host operation is available this filter has nothing to query — keep the candidate rather than blocking or reaching for a network tool.

Tiers flagged `last-resort: true` are skipped if any prior tier yielded a candidate.

### Step 2: Cross-reference with open items

For tier 1 and tier 4 (recurring candidates), cross-reference against open items — the recurring-issues automation may have already created one (adapter: "List items", `--label <resolved recurring-maintenance label>`). Pass an explicit `--limit` covering every open recurring issue: the default truncation would silently drop rows, so a bare read can miss an existing `[Maintenance]` issue and wrongly fall through to the create path below, duplicating it — page per the adapter "List items" note if they exceed the max page size. Match against the FULL expected title `[Maintenance] {schedule item title}` — exact match, never a prefix or substring. A prefix match would let a shorter title (`[Maintenance] Review CI`) spuriously match a longer item (`[Maintenance] Review CI workflow pins`), so one schedule row could be treated as already holding another row's item and skip creating its own. This mirrors the same exact-title rule in the `/work-items:track due` action.

**Due-recurring tiers (`where: 'next_due <= today'`):** if no open item exists, create one via the `/work-items:track add` action pattern before claiming. These items are actionable now — dead-ending without an item to hold would strand work.

**Last-resort recurring tiers (`last-resort: true` AND `where: 'next_due > today'`):** by design the consuming repo's recurring-issues automation typically creates items only when `next_due <= today`, so there is usually no open item to hold. Since picking early shifts the cadence, **skip last-resort candidates that have no open item and advance to the next candidate**. Only hold/claim a last-resort item when an open one already exists. If every last-resort candidate is skipped for lack of an item, report "no actionable work" rather than forcing one into existence.

### Step 3: Present and confirm

Because the frontier is already unassigned + unblocked, present the top candidate directly — no pre-hold is needed (the seam `claim` in Step 4 is the atomic acquisition point):

```
**Auto-selected (<tier-name>):** #42 Fix <thing>
Type: Bug · Labels: area: <your-area>, priority:<your-priority>

Proceed with this item? (yes / pick different / skip)
```

**Autonomous invocation (no interactive user).** When this skill is invoked by a loop lane (e.g.
`/work-items:work-loop`) or in another unattended context, there is no user to answer this prompt —
do not present it and do not block. The confirmation is satisfied by the invoker's own admission
decision: the invocation names the already-admitted item id and states that its admission gate
passed (for a loop lane, the work-class gate plus any required ratification marker — the lane's
own inlined contract). The named id **binds the selection**: skip the selection steps entirely —
do not recompute priorities or re-select — and proceed from the staleness pre-check with exactly
that item, so the invoker's admission decision and accounting stay attached to the item actually
executed (a concurrent invoker relies on this to avoid two slots colliding on the same top
candidate; the seam claim still arbitrates any true race). Record the auto-confirmation in the
item's claim comment instead of the transcript prompt. Every later step is unchanged — the seam claim in Step 5
remains the atomic acquisition point, attended or not.

### Step 4: Staleness pre-check

Before claiming, verify the item is still actionable:

- If it references a file to modify: check the file exists and the item is still relevant.
- If it references a test to add: check whether similar tests already exist.
- If stale (work already done): close it with a comment (adapter: "Close item") and advance to the next candidate.

### Step 5: Claim and execute

> **The seam claim (assignee + lease) is a non-optional prerequisite of this step — claim-before-dispatch is an invariant this skill enforces, not merely an implication of the sub-step ordering below.** An external loop-prompt or standing-rule that restates "dispatch every picked issue to a subagent in its own out-of-tree worktree" describes only the execute sub-step; it is **not** a complete execution contract and is **not** a substitute for claiming. Worktree isolation is not a race-safe collision signal between concurrent lanes — the seam claim is. Acquire the claim first, before branching or dispatching a subagent, regardless of whether the invoking loop-prompt mentioned claiming: dispatching a subagent before the claim is held is a defect even when the loop-prompt's own wording never named the claim step.

On user confirmation ("yes"):

1. **Claim via the seam** — the atomic, race-safe acquisition (assign `@me` → lease → back off on a foreign earlier lease):

   ```bash
   TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
   [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
   "$TRACKER" claim "<id>"
   ```

   `<id>` MUST be fully-qualified (`claim` rejects a bare number): frontier candidates (tiers 2/3) already carry it from `list-frontier`; a recurring candidate matched to an open item by `number` (Step 2) is first qualified via adapter "Resolve item ID". Exit `0` → claim held. Exit `7` → another session won: advance to the next candidate (do NOT retry the same item). Claim identity is the authenticated session user, never the bot.

1. **Suggest branch name.** Propose `<type>/<N>-<slug>` so `/pull-request create` can auto-inject `Closes #N` from the branch parse. Same protocol as the `/work-items:track start` action's branch-name step ([`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/start.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/start.md) "Suggest branch name") — branch `<type>` vocabulary derived from the item's issue type (native Issue Type preferred, `type:*` label fallback), slug from title (kebab-case, 40-char cap), existing-branch detection, multi-claim 3-option (switch / stay+cover-both / skip). Agent emits `git checkout -b ...` for the user; never executes itself. Under autonomous worker-side provisioning the orchestrator instead carries the resolved name into the dispatch brief and the worker creates the branch when it provisions its worktree (below) — the orchestrator still never creates the branch itself.

1. **Execute — orchestrator-dispatch is the default (`#451`).** For autonomous execution the default posture is orchestrator, not inline editor: this skill picks and claims the item, then **dispatches a scope-fenced implementation subagent** that does the source edits in its **own out-of-tree worktree** (lifecycle owned by `/source-control:worktree`, one per pick), collects the return, verifies it, and does the bookkeeping. **The orchestrator never edits source itself.** All dispatch *mechanics* — worker-brief composition, orchestrator-never-edits, verify-returns-against-evidence, and the concurrent-wave cap — are owned by `/implementation:implement-dispatch`; chain to it rather than re-describing them here. An interactive, all-inline run instead uses `/implementation:implement`. Whichever path runs, the executing surface MUST follow every step of the consuming project's development workflow (a workflow skill, a `CLAUDE.md` workflow section, or team convention) and read the project's rules for the item's domain first — no shortcuts, no skipping research, no surface-level execution; dispatch is only *how* that workflow is carried out. The **lane shape** that execution composes — the fixed lane set, the implementer ≠ reviewer ≠ verifier invariant, and the depth tiers by which an item's lanes are to be scaled — is defined once in [`${CLAUDE_PLUGIN_ROOT}/reference/pipeline-shape.md`](${CLAUDE_PLUGIN_ROOT}/reference/pipeline-shape.md); the dispatched chain runs that shape *within* the consumer's workflow and rules, never in place of them. **Autonomous branch/worktree provisioning is worker-side (`#572`).** An autonomous run reaches a non-default branch/worktree *before* the dispatch preflight by making provisioning the dispatched worker's own first step: the worker materializes an isolated out-of-tree worktree — through `/source-control:worktree`'s non-entering creation seam when the `source-control` plugin is installed (that skill owns naming, placement, and cleanup conventions), or a plain `git worktree add` otherwise — and works against it via `git -C <path>` **without entering it**, per `/implementation:implement-dispatch`'s worktree-cwd contract. The branch name is the one the *Suggest branch name* sub-step above resolved, carried in the dispatch brief; the worker attaches it to the worktree with `git worktree add -b <name> <path> <base>` for a **new** branch, or `git worktree add <path> <name>` (no `-b`) when that sub-step already detected the branch as **existing** — `-b` fails outright on an existing branch, including one the user created by following that sub-step — so the `Closes #N` the name encodes reaches the orchestrator's PR. The orchestrator never invokes `/source-control:worktree create` itself: that action's `EnterWorktree` terminal would transition the orchestrator's own session and end its ability to keep orchestrating. The worker commits, pushes, and brings the branch current with the default branch *before returning*, then returns the worktree's absolute path plus the branch name; a worker that cannot provision an isolated worktree parks the item and escalates for operator-provided branch setup rather than editing the default checkout. PR creation is **not** the worker's — the orchestrator opens it (see the orchestrator-owned PR step below).

   **The dispatch brief carries the PR contract forward (`#462`).** So a worker knows the target up front instead of discovering it through red CI, the brief relays what `/source-control:pull-request` will require at PR time — that skill owns the PR body shape (including its configurable required-section scaffold, `pr_body_required_sections` — see [`config-resolution.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/reference/config-resolution.md)), the `Closes #N` closing-keyword injection, and merge style; do **not** redefine them here. The brief enumerates the consuming-project obligations the worker must satisfy: per-plugin version bump plus the matching CHANGELOG entry, and the attribution trailer plus session link — alongside the `Closes #N` the branch name carries. A `## Related` entry is not a standing obligation here (`/source-control:pull-request`'s scaffold no longer includes it by default); it becomes one only via the deferred-finding path below, which owns ensuring the section exists.

   **The dispatch concurrency cap is configured via `userConfig`, never a hardcoded literal.** `${user_config.work_dispatch_concurrency_cap}` resolves to the operator's value when set; when the key is unset (it declares no manifest default) it renders as a literal `${user_config.…}` placeholder — the empirically verified unset render (same as the sibling `work_loop_item_cap_*` keys rely on) — or, defensively, an empty value. When it resolves to a positive number, the orchestrator threads it into the delegated `/implementation:implement-dispatch` dispatch as that skill's `--wave-cap <N>`, capping concurrent dispatch waves at that value; any other render — a surviving placeholder or an empty value, both meaning unset — passes **no** `--wave-cap`, so `/implementation:implement-dispatch` applies its own internal 3–5 wave default (that skill owns the wave-cap mechanics; chain to it rather than re-describing them here). That single parameter is the cap's enforcement (`#573`), so never coerce an unset placeholder or empty value into a number. **Waves are discrete, so a fractional cap is floored to a whole number before it becomes the argument** — pass `⌊value⌋` (e.g. `1.5` → `1`), never below the manifest's `min` of `1`: the manifest `type` is `number` (the userConfig schema has no integer type), so a non-whole value is possible, and flooring keeps the operator's ceiling conservative rather than rounding up past their intent. Never fall back to the internal 3–5 default on a fractional value — that would silently *raise* concurrency above the operator's lower ceiling. `--wave-cap` is honored by the `/implementation:implement-dispatch` version that documents it (implementation `0.9.0`+); this marketplace ships `work-items` and `implementation` together and bumps them per PR, so the delegated flag normally lands on a sibling that supports it. An installation whose `implementation` predates the parameter degrades gracefully — the unrecognized flag is dropped and that skill's internal 3–5 default applies, identical to an unset cap, never a misfire — the same plugins-move-together, presence-gated coupling the orchestrator-owned PR step relies on for `/source-control:pull-request create --pushed` (`#572`), not a manifest version dependency (this marketplace declares none). **A per-cycle item budget is not this skill's concern:** `work` selects and executes exactly one item per invocation, so it has no cycle to bound; the autonomous per-cycle item budget lives in the driving loop — the `work-loop` lane's adaptive item cap (`work_loop_item_cap_*`), enforced by the loop body's own arithmetic. **Same-plugin serialization is deferred to `#464`:** until it lands, treat two in-flight items in the same plugin as an awareness note — prefer not to dispatch a second concurrently, since their diffs and version/CHANGELOG bumps can collide.

1. **High-blast-radius diff gate (pre-PR).** Before a PR is opened, the orchestrator does a **full-diff read** when the diff touches skill frontmatter descriptions or trigger keywords, cross-plugin contracts, or hooks — read against the worker's returned worktree (`git -C <path>`), since the orchestrator's own default-branch checkout does not contain the worker's changes. This complements the worker scope-fence: the scope-fence bounds what a worker *may* touch, this gate is the orchestrator's own read of what the worker *did* touch before the change leaves the lane.

1. **Open the PR — orchestrator-owned (`#572`).** After the worker returns and the pre-PR diff gate passes, the **orchestrator** opens the PR — it is never the worker's to open (opening it from a worker would make the pre-PR gate a no-op, and `/implementation:implement-dispatch` already keeps PR creation out of every worker brief). The worker committed and pushed inside its own worktree, so the orchestrator invokes the **PR-only entry** `/source-control:pull-request create --pushed --worktree <the worker's returned worktree path>` — passing that path explicitly, since the orchestrator stays in its own (default-branch) checkout and the mode needs the path to resolve the worker's branch and diff rather than the orchestrator's. That mode re-resolves branch and diff from the target worktree and skips the commit/push/rebase steps the normal `create` runs, while `/source-control:pull-request` stays the SSOT for the PR body shape, the `Closes #N` closing-keyword injection, the required-section gate, and merge style. **Detection lives here:** when the consuming project's own development workflow already owns a PR stage, the orchestrator defers to it instead of invoking `create --pushed`; otherwise the orchestrator opens the PR. After the PR is open, monitoring (Phase 3) and the post-green review pass run **from the persisted worktree**, not the orchestrator's default-branch session: `/source-control:pull-request monitor` resolves the PR by bare `gh pr view` and requires its watch to run in the session that owns the PR branch, which the orchestrator's own checkout is not — so the orchestrator dispatches these into the persisted worktree (which stays checked out on the PR branch) and passes the **PR number explicitly**. Any **branch-owned fix** (a failing check or a review finding) is applied by re-dispatching a **fresh scope-fenced subagent into that same persisted worktree** (`git -C <path>`) — never by the orchestrator editing source, and a fresh scoped brief rather than resuming the original worker because the worktree, not the subagent, is the state carrier across dispatches.

1. **Post-green review pass, then hand off.** After CI is green, run one review pass. The fetch-once → validate → classify → threaded-reply → react → resolve-bot-thread loop is owned by `/source-control:pull-request`; this skill adds only the sequencing and the work-item linkage: fix branch-owned findings via the same **fresh-subagent-into-the-persisted-worktree** re-dispatch the orchestrator-owned PR step defines (the orchestrator still never edits source), and a **VALID-but-deferred finding requires a filed follow-up issue** — file it via `/work-items:track add` following the shared self-observation contract ([`${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md`](${CLAUDE_PLUGIN_ROOT}/reference/dogfood-filing.md): dedupe → categorize → fixed shape → `needs-triage`), then cite that issue **both** in the classification reply **and** in the PR's `## Related` section — **ensure the section exists first**: `/source-control:pull-request`'s scaffold carries `## Related` only when the repo's `pr_body_required_sections` requires it or a genuine reference already populated it at create time, so a deferred finding is frequently the first content that section ever holds. Adding it is a **read-modify-write**, never a bare `--body` replacement — `gh pr edit --body`/`--body-file` REPLACES the whole body (the same identity note the GitHub adapter's [PR closing-keyword mechanics](../../tools/work-item-tracker/adapters/github/README.md) documents for its own body edit), so read the current body first (`gh pr view <N> --json body --jq '.body'`), append the `## Related` section (or its content, if the section already exists) to that read, and write the combined result back via `--body-file -`; a bare `gh pr edit --body "## Related\n..."` would silently drop `Closes #N`, Summary, and Test plan. A deferred finding cannot be resolved without it. Then hand the PR off to `/source-control:babysit-prs` (fleet loop, owned there).

1. **Never-merge boundary.** This skill's lane ends at PR creation and the handoff above (review pass, then babysit). **Merging is the babysit lane or a human, never `work`** — consistent with `/source-control:babysit-prs`'s safe default never merging (its opt-in `worker`/`autopilot` tiers merge only behind a deterministic readiness gate) and `/source-control:pull-request` merges being human-gated. The worker's worktree **persists** through the whole PR lifecycle — the same-worktree fix re-dispatch above depends on it — and is cleaned up only by whoever merges (`/source-control:pull-request merge` Phase 4, the babysit worker tier, or a human via `/source-control:worktree cleanup`), never mid-lifecycle and never by this lane.

1. **On completion:** run `/work-items:track done` (one-off items) or `/work-items:track recheck` (recurring items).

## Bug Investigation Rule

Reproduce the reported failure FIRST. Never close a bug item without either reproducing and fixing it, or proving via git history why the reporter saw the failure and why it no longer applies.
