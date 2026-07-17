# Tracker mechanics — the `gh` commands

`/wayfind` operates the map through the GitHub Issues backend directly, the same idiom as the
sibling `/work-items` skill (backend-agnostic "work items" language, plain `gh`). All commands
run against the current repository. Where the consuming project routes tracker **writes**
through a bot identity or wrapper, follow that project's own rules — with one exception: the
claim assignment (`--add-assignee "@me"`) always runs on the session identity, never a shared
bot, or the collision check silently breaks.

Native primitives (gh ≥ 2.94): sub-issues via `--parent`, dependency edges via
`--add-blocked-by` (or `--blocked-by` at create time), both queryable as JSON fields.
**Shape gotcha (verified live):** `subIssues` and `blockedBy` are objects — `{"nodes": [...],
"totalCount": N}` — NOT flat arrays. Use `.subIssues.nodes[]` and read blockers from
`.blockedBy.nodes[]`; `.blockedBy | length` returns the key count (always 2), never the
blocker count. (`assignees` and `labels` ARE flat arrays — `| length` is correct for those.)
**A closed blocker stays in the edge set** — `blockedBy.totalCount` still counts it after it
closes. Frontier must count only **OPEN** blockers (`.blockedBy.nodes[] | select(.state=="OPEN")`),
or every item whose blocker ever closed is stranded off the frontier forever.

## Bootstrap labels (first use in a repo)

`/wayfind` uses its own taxonomy — `work-map`, `wayfind: research|interview|design|prototype|task`
(axis labels follow the colon-space grammar so label-as-code owners with a `prefix: value` convention
can declare them verbatim), `needs-human`. At chart-mode entry, **verify** the taxonomy is present because an unknown `--label`
fails `gh issue create`. Read the consuming repository's instructions and configuration for label
ownership. If they declare a label-as-code source of truth, treat that declared system as the writer,
report the exact missing set to its owner, and stop. If no ownership policy is declared, report the
missing set and ask the user how labels are provisioned. The plugin never assumes an organization or
provisioning repository and never creates labels ad hoc:

```shell
# Presence check only — never create. Route missing labels to the repository-declared owner.
have=$(gh label list --json name --jq '.[].name')
for L in work-map 'wayfind: research' 'wayfind: interview' 'wayfind: design' 'wayfind: prototype' 'wayfind: task' needs-human; do
  grep -qxF "$L" <<<"$have" || echo "MISSING (route to repository label owner): $L"
done
```

## Create / extend the map

```shell
# Map issue: bare `work-map` marker + any repo program labels. Body per context/map-anatomy.md.
gh issue create --title "Map: <effort>" --label work-map --body-file <map-body.md>
```

A map is never assigned and never carries a claim label — it is a container, not a work item.

## Create a typed decision item (sub-issue of the map)

```shell
# Type label routes + sets default mode. HITL types add `needs-human`; research omits it.
gh issue create --parent <map#> \
  --title "<sharp question>" \
  --label "wayfind: <research|interview|design|prototype|task>" \
  --body "<what must be decided, options if known, the item body picks logic/ui for prototype>"

# HITL item — materialize the mode:
gh issue edit <item#> --add-label needs-human      # interview | design | prototype (default)
# research → leave `needs-human` off (autonomous-capable). task → per-item.
```

## Wire a dependency edge (only where one decision genuinely gates another)

```shell
gh issue edit <item#> --add-blocked-by <blocker#>
```

Never invent edges to impose order — an edge means the blocker's resolution is a genuine
precondition for phrasing or answering the dependent decision.

## Compute the frontier

`frontier = open ∧ blocked-by count == 0 ∧ unassigned` (in non-interactive sessions, also
`∧ NOT needs-human`). Core-side derivation over the map's sub-issues — no server-side search
syntax needed:

```shell
# 1. Sub-issue numbers of the map (subIssues is {nodes,totalCount} — read .nodes).
MAP=<map#>
gh issue view "$MAP" --json subIssues --jq '.subIssues.nodes[].number' | tr -d '\r' | while read -r n; do
  # 2. Per item: keep open, zero blockers, no assignee (blockedBy is {nodes,totalCount} — read .totalCount).
  gh issue view "$n" --json number,title,state,blockedBy,assignees,labels --jq '
    select(.state == "OPEN")
    | select(([.blockedBy.nodes[] | select(.state == "OPEN")] | length) == 0)
    | select((.assignees | length) == 0)
    | "#\(.number) \(.title) [\([.labels[].name] | map(select(startswith("wayfind: ")))[])]"' | tr -d '\r'
done
# Non-interactive: also drop needs-human items — add
#   | select((.labels | map(.name) | index("needs-human")) | not)
# to the per-item jq filter above.
```

## Claim a frontier item (mirrors `/work-items` — one claim model across both skills)

Optimistic locking via **claim-comment order** (the sibling's mechanism). Assignee comparison
is NOT sufficient: two same-identity sessions both assign `@me` and resolve to one login, so
neither can tell who won. The discriminator is the claim comment — GitHub timestamps each, and
the earliest wins. Embed a per-session marker in the comment so you can recognize your own.

```shell
# 1. Pre-check (read): not already assigned by someone else. The claim is assignee + lease —
#    there is NO claim label.
gh issue view <item#> --json assignees \
  --jq '{assignees:[.assignees[].login]}' | tr -d '\r'

# 2. Post a claim marker comment (the lease — embed a per-session marker), then assign self.
#    @me MUST be the session identity so the timeline is honest.
gh issue comment <item#> --body "🔒 claim: <session-marker>"
gh issue edit <item#> --add-assignee "@me"

# 3. Collision check via claim-comment ORDER (not assignees). The EARLIEST claim comment wins.
gh issue view <item#> --json comments \
  --jq '[.comments[] | select(.body | startswith("🔒 claim:"))] | sort_by(.createdAt) | .[0].body' | tr -d '\r'
#    If the earliest claim comment is NOT yours (marker mismatch): back off — delete your claim
#    comment. Re-read assignees (step 1's command): if another login besides your own is present
#    (a foreign race — the winner assigned under a different identity), remove ONLY your own
#    assignee. If you are the item's sole assignee, leave it: a same-identity `@me` collision
#    means that slot is shared with the winner, so removing it would also un-claim their item and
#    let it re-enter the frontier out from under them. Either way, pick the next frontier item.
```

Session-start `reclaim` is idempotent: clear your own assignee (and claim comment) on items you
hold that have no in-progress signal (open PR / branch pushes / recent comments), noting the
release in a comment.

## Graduate + close a decision item (atomic: comment → index → close)

```shell
# 1. Resolution comment on the item (the decision's durable home).
gh issue comment <item#> --body "Resolved: <decision> — <one-line basis>"
# 2. Add the one-line pointer to the map's Decisions-so-far index (edit the map body).
# 3. Close the item (closing removes it from the frontier — the claim is assignee + lease, no label to clear).
gh issue close <item#> --reason completed
```

## Close the map (frontier empty ∧ all items closed)

```shell
gh issue close <map#> --reason completed \
  --comment "Destination coherent — handed to <\/planning:interview | \/planning:prd | \/planning:architect>."
```
