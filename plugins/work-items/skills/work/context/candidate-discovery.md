# Candidate discovery: finding and cross-referencing

Steps 1 and 2 of the workflow in [`../SKILL.md`](../SKILL.md), which runs them after the
role-label preflight and before Step 3 presents anything to the user. The tier ladder these queries
serve stays in the hub; this file owns how each tier is queried and which candidates survive.

## Contents

- [Step 1: Find candidates](#step-1-find-candidates)
- [Step 2: Cross-reference with open items](#step-2-cross-reference-with-open-items)

## Step 1: Find candidates

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

  `--autonomous` additionally excludes items carrying the human-gated role label (`needs-human` by default. [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles"). Tier 2 keeps only `area: guardrails` items that do not carry the resolved recurring-maintenance label; tier 3 keeps the rest of that non-recurring set. The normalized frontier model omits `createdAt`, so apply tier 3's **oldest-first** ordering by sorting the candidates on `createdAt` from the adapter "List items" projection (over the frontier numbers) before picking the top one. Pass an explicit `--limit` covering the whole frontier on that projection so the default truncation can't hide an older candidate outside the first page and defeat the oldest-first pick (page per the adapter "List items" note if the frontier exceeds the max page size). Provider search syntax never leaves the adapter, the label filter runs over the labels `list-frontier` already returns.

**Exclude in-flight frontier candidates (open linked PR).** A frontier candidate (tiers 2–3) that already has an open PR targeting it for closure is work already in flight. Drop it from the pickable set so it is not re-picked. For each surviving frontier number, query the bound adapter's *open linked PRs* operation (GitHub: [`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md) "Open linked PRs") and exclude the number when it reports an open PR closing that item. The **closing-keyword linkage** is the authoritative signal, the same `Closes #N` / native-closing-keyword linkage `pr-issue-linkage` enforces (owned by `/source-control:pull-request`), so an intentional `Refs #N` opt-out does not exclude its issue. Provider search syntax never leaves the adapter, this filter reads only the open-closing-PR boolean the adapter returns per number. **Fail closed when the in-flight check itself fails:** a query that errors (the adapter operation exits non-zero and returns no boolean, expired token, rate limit, network error) is *not* a `false`; exclude the number this cycle rather than treating an unconfirmed check as "no open PR", which would re-dispatch precisely when in-flight state could not be verified. **Fail open when the bound provider exposes no PR host:** the offline `local-markdown` binding is never a coordination surface and touches no network tool ([`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md) "local-markdown adapter"), so when no PR-host operation is available this filter has nothing to query. Keep the candidate rather than blocking or reaching for a network tool.

Tiers flagged `last-resort: true` are skipped if any prior tier yielded a candidate.

## Step 2: Cross-reference with open items

For tier 1 and tier 4 (recurring candidates), cross-reference against open items, the recurring-issues automation may have already created one (adapter: "List items", `--label <resolved recurring-maintenance label>`). Pass an explicit `--limit` covering every open recurring issue: the default truncation would silently drop rows, so a bare read can miss an existing `[Maintenance]` issue and wrongly fall through to the create path below, duplicating it. Page per the adapter "List items" note if they exceed the max page size. Match against the FULL expected title `[Maintenance] {schedule item title}`. Exact match, never a prefix or substring. A prefix match would let a shorter title (`[Maintenance] Review CI`) spuriously match a longer item (`[Maintenance] Review CI workflow pins`), so one schedule row could be treated as already holding another row's item and skip creating its own. This mirrors the same exact-title rule in the `/work-items:track due` action.

**Due-recurring tiers (`where: 'next_due <= today'`):** if no open item exists, create one via the `/work-items:track add` action pattern before claiming. These items are actionable now. Dead-ending without an item to hold would strand work.

**Last-resort recurring tiers (`last-resort: true` AND `where: 'next_due > today'`):** by design the consuming repo's recurring-issues automation typically creates items only when `next_due <= today`, so there is usually no open item to hold. Since picking early shifts the cadence, **skip last-resort candidates that have no open item and advance to the next candidate**. Only hold/claim a last-resort item when an open one already exists. If every last-resort candidate is skipped for lack of an item, report "no actionable work" rather than forcing one into existence.

**Standing-item preconditions (tiers 1 and 4).** After a recurring candidate is identified and before cross-reference/claim, evaluate any `precondition` on its schedule row ([`${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md`](${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md)):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
EVAL="${CLAUDE_PLUGIN_ROOT}/scripts/evaluate-schedule-precondition.sh"
[[ -f "$EVAL" ]] || EVAL="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/plugins/work-items/scripts/evaluate-schedule-precondition.sh"
"$EVAL" "$SCHEDULE" "<schedule-item-id>"   # add --operator-confirmed when the operator affirmed
```

- Exit `0` with `met` or `no-precondition` → proceed.
- Exit `2` with `needs-confirmation` → surface the printed `prompt` inline, **skip this candidate**, and do not claim. Autonomous invocations must skip without claiming unless the invocation explicitly records operator confirmation for that schedule id (then pass `--operator-confirmed`).
- Exit `1` with `unmet` → skip the candidate and report why.

This is what makes #2019's tier-4 caveat enforceable instead of convention-only prose in the issue body.
