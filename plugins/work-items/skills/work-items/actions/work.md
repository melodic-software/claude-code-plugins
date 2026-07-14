# Action: `work`

Auto-select one work item and execute it, following the project's development workflow.

## Usage

```
/work-items:work-items work
```

## Step 0: Session-start reclaim (idempotent)

Before selecting, clear stale claims left by crashed or abandoned sessions (an idempotent entry step). Enumerate currently-assigned items (adapter: "List items", assigned filter — the rows carry `number`), resolve each `number` to a fully-qualified id (adapter: "Resolve item ID"; `reclaim` rejects a bare number), and run the seam `reclaim` verb on each id — idempotent; outcome + activity-check semantics per `tools/work-item-tracker/CONTRACT.md` "Lease protocol".

```bash
"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" reclaim "<id>"
```

## Selection Priority

`/work-items:work-items work` evaluates these tiers top-down, only falling through to the next tier when the current one yields no candidates. Tiers flagged last-resort are skipped if any prior tier already yielded a candidate.

1. **Due recurring items** — `recurring-schedule`, where `next_due <= today`, sorted by `next_due`. Schedule commitments take precedence over category flags; picking a recurring item early shifts its subsequent cadence and undermines the recurrence guarantee.

2. **Non-recurring guardrails items** — the frontier (open ∧ unblocked ∧ unassigned) filtered to `area: guardrails` (when the repo defines that area), non-recurring. Force multipliers — each one completed makes ALL future autonomous work more reliable. Within this tier, prefer: enforcement mechanisms (CI/CD gates, architecture tests, hooks) > tool validation > research/planning.

3. **Highest-impact non-recurring unassigned items** — the remaining frontier, non-recurring, oldest-first. Select based on: items that unblock others, items in smaller categories, shorter well-scoped items over sprawling research epics.

4. **Recurring items not yet due** (last-resort) — `recurring-schedule`, where `next_due > today`, sorted by `next_due`. LAST RESORT only, when tiers 1–3 are empty. Picking a recurring item before its `next_due` shifts the cadence forward — avoid unless nothing else is available. Prefer items closest to `next_due` (least cadence disruption).

## Workflow

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
  "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" list-frontier --autonomous
  ```

  `--autonomous` additionally excludes `needs-human` items. Tier 2 keeps only `area: guardrails` non-recurring; tier 3 keeps the rest. The normalized frontier model omits `createdAt`, so apply tier 3's **oldest-first** ordering by sorting the candidates on `createdAt` from the adapter "List items" projection (over the frontier numbers) before picking the top one — pass an explicit `--limit` covering the whole frontier on that projection so the default truncation can't hide an older candidate outside the first page and defeat the oldest-first pick (page per the adapter "List items" note if the frontier exceeds the max page size). Provider search syntax never leaves the adapter — the label filter runs over the labels `list-frontier` already returns.

Tiers flagged `last-resort: true` are skipped if any prior tier yielded a candidate.

### Step 2: Cross-reference with open items

For tier 1 and tier 4 (recurring candidates), cross-reference against open items — the recurring-issues automation may have already created one (adapter: "List items", `--label recurring`). Pass an explicit `--limit` covering every open recurring issue: the default truncation would silently drop rows, so a bare read can miss an existing `[Maintenance]` issue and wrongly fall through to the create path below, duplicating it — page per the adapter "List items" note if they exceed the max page size. Match against the FULL expected title `[Maintenance] {schedule item title}` — exact match, never a prefix or substring. A prefix match would let a shorter title (`[Maintenance] Review CI`) spuriously match a longer item (`[Maintenance] Review CI workflow pins`), so one schedule row could be treated as already holding another row's item and skip creating its own. This mirrors the same exact-title rule in the `due` action.

**Due-recurring tiers (`where: 'next_due <= today'`):** if no open item exists, create one via the `add` action pattern before claiming. These items are actionable now — dead-ending without an item to hold would strand work.

**Last-resort recurring tiers (`last-resort: true` AND `where: 'next_due > today'`):** by design the consuming repo's recurring-issues automation typically creates items only when `next_due <= today`, so there is usually no open item to hold. Since picking early shifts the cadence, **skip last-resort candidates that have no open item and advance to the next candidate**. Only hold/claim a last-resort item when an open one already exists. If every last-resort candidate is skipped for lack of an item, report "no actionable work" rather than forcing one into existence.

### Step 3: Present and confirm

Because the frontier is already unassigned + unblocked, present the top candidate directly — no pre-hold is needed (the seam `claim` in Step 4 is the atomic acquisition point):

```
**Auto-selected (<tier-name>):** #42 Fix <thing>
Type: Bug · Labels: area: <your-area>, priority:<your-priority>

Proceed with this item? (yes / pick different / skip)
```

### Step 4: Staleness pre-check

Before claiming, verify the item is still actionable:

- If it references a file to modify: check the file exists and the item is still relevant.
- If it references a test to add: check whether similar tests already exist.
- If stale (work already done): close it with a comment (adapter: "Close item") and advance to the next candidate.

### Step 5: Claim and execute

On user confirmation ("yes"):

1. **Claim via the seam** — the atomic, race-safe acquisition (assign `@me` → lease → back off on a foreign earlier lease):

   ```bash
   "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" claim "<id>"
   ```

   `<id>` MUST be fully-qualified (`claim` rejects a bare number): frontier candidates (tiers 2/3) already carry it from `list-frontier`; a recurring candidate matched to an open item by `number` (Step 2) is first qualified via adapter "Resolve item ID". Exit `0` → claim held. Exit `7` → another session won: advance to the next candidate (do NOT retry the same item). Claim identity is the authenticated session user, never the bot.

1. **Suggest branch name.** Propose `<type>/<N>-<slug>` so `/pull-request create` can auto-inject `Closes #N` from the branch parse. Same protocol as `start.md` "Workflow" final step — branch `<type>` vocabulary derived from the item's issue type (native Issue Type preferred, `type:*` label fallback), slug from title (kebab-case, 40-char cap), existing-branch detection, multi-claim 3-option (switch / stay+cover-both / skip). Agent emits `git checkout -b ...` for the user; never executes itself.

1. **Execute the project's development workflow:** the agent MUST follow every step — no shortcuts, no skipping research, no surface-level execution. When the consuming project defines a workflow (a workflow skill, a CLAUDE.md workflow section, or team convention), follow every step of it and read the project's rules for the item's domain first; otherwise follow the generic sequence: explore → plan → implement → test → review → PR.

1. **On completion:** run the `done` action (one-off items) or `recheck` action (recurring items).

## Bug Investigation Rule

Reproduce the reported failure FIRST. Never close a bug item without either reproducing and fixing it, or proving via git history why the reporter saw the failure and why it no longer applies.
