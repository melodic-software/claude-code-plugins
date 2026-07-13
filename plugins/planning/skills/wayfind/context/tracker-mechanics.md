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

`/wayfind` introduces its own taxonomy — `work-map`, `wayfind:research|interview|design|prototype|task`,
`needs-human` — which a fresh consumer repo will NOT already have (unlike the type/status labels
`/work-items` reuses). Create-if-missing them once at chart-mode entry, before the first `gh issue
create --label` (an unknown `--label` fails the create):

```shell
for L in work-map wayfind:research wayfind:interview wayfind:design wayfind:prototype wayfind:task needs-human; do
  gh label list --json name --jq '.[].name' | grep -qxF "$L" || gh label create "$L" --description "wayfind decision-map taxonomy"
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
  --label "wayfind:<research|interview|design|prototype|task>" \
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
    | "#\(.number) \(.title) [\([.labels[].name] | map(select(startswith("wayfind:")))[])]"' | tr -d '\r'
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
# 1. Pre-check (read): not already claimed/assigned by someone else.
gh issue view <item#> --json assignees,labels \
  --jq '{assignees:[.assignees[].login], claimed:([.labels[].name]|any(.=="status:claimed"))}' | tr -d '\r'

# 2. Ensure the claim label exists, post a claim marker comment (embed a per-session marker),
#    then assign self + label. @me MUST be the session identity so the timeline is honest.
gh label list --json name --jq '.[].name' | grep -qxF status:claimed || gh label create status:claimed --description "Claimed by a work session"
gh issue comment <item#> --body "🔒 claim: <session-marker>"
gh issue edit <item#> --add-label status:claimed --add-assignee "@me"

# 3. Collision check via claim-comment ORDER (not assignees). The EARLIEST claim comment wins.
gh issue view <item#> --json comments \
  --jq '[.comments[] | select(.body | startswith("🔒 claim:"))] | sort_by(.createdAt) | .[0].body' | tr -d '\r'
#    If the earliest claim comment is NOT yours (marker mismatch): back off — remove ONLY your own
#    assignee (never the shared status:claimed label the winner holds), delete your claim comment,
#    and pick the next frontier item.
```

Session-start `reclaim` is idempotent: clear your own `status:claimed` + assignee on items you
hold that have no in-progress signal (open PR / branch pushes / recent comments), noting the
release in a comment.

## Graduate + close a decision item (atomic: comment → index → close)

```shell
# 1. Resolution comment on the item (the decision's durable home).
gh issue comment <item#> --body "Resolved: <decision> — <one-line basis>"
# 2. Add the one-line pointer to the map's Decisions-so-far index (edit the map body).
# 3. Close the item.
gh issue edit <item#> --remove-label status:claimed
gh issue close <item#> --reason completed
```

## Close the map (frontier empty ∧ all items closed)

```shell
gh issue close <map#> --reason completed \
  --comment "Destination coherent — handed to <\/planning:interview | \/planning:prd | \/planning:architect>."
```
