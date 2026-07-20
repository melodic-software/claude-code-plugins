# GitHub adapter — operations reference

Concrete `gh` mechanics for the `/work-items` skill's **non-coordination** operations against
the GitHub provider. Coordination (create / claim / lease / link / frontier) runs through the
seam verbs (`work-item-tracker.sh <verb>`, see `../../CONTRACT.md`); the operations below —
listing with arbitrary filters, search, aggregation, close, label/comment edits — have no core
verb by design (they carry provider-specific search/filter syntax the seam contract keeps out of
core), so the skill core describes them neutrally and resolves the mechanics here.

The commands below are standard GitHub CLI (`gh`); each layers only the work-items-specific
`--json`/`--jq` projection on top. **Identity (writes):** reads use bare `gh`; writes (close,
label/comment edits, PR-body edits) route through an optional bot wrapper when the consuming repo
provides one and fall back to bare `gh` otherwise (seam identity routing: `../../CONTRACT.md`
"Identity routing (GitHub adapter)"). The examples show bare `gh`; substitute your repo's bot
wrapper for write ops if it uses one. Claim assignment always stays on bare `gh` (`@me` must be the
session identity). Every pipeline parsing `gh` JSON on Windows/Git Bash ends with `| tr -d '\r'`
(see "Gotchas").

## Available `--json` fields

Do NOT hardcode the field set — GitHub adds fields over time (the dependency/parent/sub-item
fields the seam's normalized model reads — `blockedBy`, `parent`, `subIssues` — are recent
additions). Derive the current valid set on demand: `gh issue list --json` (no value) prints it.

## Resolve item ID

Seam verbs (`get-item`, `claim`, `reclaim`, `link-blocks`, `add-sub-item`) take a
fully-qualified ID (`github:<owner>/<repo>#<N>` — CONTRACT.md "ID grammar"); a bare `#N` is
rejected. The **seam** verbs (`list-frontier`, `get-item`, `create-item`) already emit the
qualified `id` — pass it straight through. The adapter's raw `list` / `search` projections below
emit only `number`, so build the qualified ID from the number:

```bash
PREFIX="$(gh repo view --json owner,name -q '"github:\(.owner.login)/\(.name)"' | tr -d '\r')"
ID="${PREFIX}#<N>"
```

## List items

Arbitrary filter projection (bare `gh`):

```bash
gh issue list \
  ${LABEL:+--label "$LABEL"} \
  ${ASSIGNEE:+--assignee "$ASSIGNEE"} \
  ${SEARCH:+--search "$SEARCH"} \
  --state "${STATE:-open}" \
  --json number,title,state,labels,assignees,createdAt,updatedAt \
  --limit "${LIMIT:-30}" \
  | tr -d '\r'
```

Forward `--assignee` for the `list --assignee` flag and the audit's assigned-only view (use
`--assignee "@me"` for the current user). `--limit` is mandatory when more than 30 rows are
needed (`gh` truncates at 30 silently; max page size 100 — for larger sets, page with `--search`
date ranges).

## Search items

Search with `--search` (GitHub search syntax, not `gh` flags):

```bash
gh issue list --search "<query>" --state open   --json number,title,state,labels,assignees --limit 20 | tr -d '\r'
gh issue list --search "<query>" --state closed --json number,title,state,labels,closedAt   --limit 10 | tr -d '\r'
```

Search-qualifier reference:

| Qualifier | Example | Meaning |
|-----------|---------|---------|
| `label:name` | `label:type:chore` | Has label |
| `-label:name` | `-label:stale` | Excludes label |
| `no:assignee` | `no:assignee` | Unassigned |
| `assignee:login` | `assignee:@me` | Assigned to user |
| `sort:field-dir` | `sort:created-asc` | Sort (created, updated, comments) |
| `created:>date` | `created:>2026-01-01` | Created after date |
| `updated:>date` | `updated:>2026-03-01` | Updated after date |
| `"exact phrase"` | `"fix authentication"` | Body/title text search |

Multiple qualifiers AND-combine: `label:type:chore label:recurring no:assignee sort:created-asc`.

## View item

View an item (bare `gh`):

```bash
gh issue view <N> --json number,title,body,labels,assignees,comments | tr -d '\r'
```

Assignee/label projection for claim pre-checks:

```bash
gh issue view <N> --json assignees,labels \
  --jq '{assignees: [.assignees[].login], labels: [.labels[].name]}' | tr -d '\r'
```

## List item comments

List an item's comments (bare `gh`):

```bash
gh api "repos/{owner}/{repo}/issues/<N>/comments" \
  --jq '[.[] | {id, user: .user.login, created_at, body}] | sort_by(.id)' | tr -d '\r'
```

## Close item

Close an item (WRITE — see the identity note above):

```bash
gh issue close <N> --comment "<closing note>" --reason completed
```

The `done` action closes with `--reason completed` (or `not planned` for `--not-planned`) — the
values GitHub's issue-close accepts.

## Edit labels / assignees

Edit labels / assignees (WRITE — see the identity note above). Edits use
`--add-label`/`--remove-label` and `--add-assignee`/`--remove-assignee` (NOT `--label`, which
is `gh issue create` only):

```bash
gh issue edit <N> --add-label "<name>" --remove-label "<name>"
```

**Carve-out — claim assignment stays on bare `gh`:** `--add-assignee "@me"` MUST resolve to the
session identity (not a bot), so it runs on bare `gh`. Coordination claims go through the seam
`claim` verb, which owns this.

## Comment on item / edit a comment

Comment on an item; edit a comment via PATCH (preserves the audit trail) — both WRITE (see the
identity note above):

```bash
gh issue comment <N> --body "<text>"
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<CID>" -f body="<text>"
```

## PR closing-keyword mechanics

For the `done` action's belt-and-suspenders keyword check. Read the PR body (bare `gh`); the
read-modify-write body edit uses `--body-file`, which REPLACES the body (WRITE — see the identity
note above):

```bash
gh pr view <PR> --json body,mergedAt --jq '.body' | tr -d '\r' > /tmp/pr-body.md
# On an UNMERGED PR lacking a closing keyword and an opt-out marker, prepend `Closes #<N>`:
printf '%s\n\n%s\n' "Closes #<N>" "$(cat /tmp/pr-body.md)" \
  | gh pr edit <PR> --body-file -
```

Match GitHub's issue-closing keyword set (`close`/`closes`/`closed`/`fix`/`fixes`/`fixed`/
`resolve`/`resolves`/`resolved`) followed by `#<num>`; the opt-out markers `Refs #<num>` /
`No related issue:` leave the body untouched.

## Open linked PRs

For `/work-items:work` selection — report whether item `<N>` already has an open PR targeting it
for closure, so a candidate whose work is in flight is dropped from the pickable frontier rather
than re-picked. `--search "<N> in:body"` is a coarse prefilter: it returns every open PR whose
body mentions the number — a superset, since a small `<N>` (e.g. `#5`) appears in many PR bodies
and GitHub sorts search by relevance, not recency. `--limit` MUST therefore exceed the repo's
open-PR count so the real closing PR is never truncated away before the precise filter runs
(`--limit 1000` covers any realistic repo; page with `--search` date ranges if a repo ever holds
more open PRs than that — see the `--limit` note under "List items"). The `jq` `test` over the
returned bodies is the authoritative match, keeping only PRs that carry a real closing keyword for
`#<N>` (bare read):

```bash
gh pr list --state open --search "<N> in:body" --json number,body --limit 1000 | tr -d '\r' \
  | jq --arg n "<N>" 'any(.[]; (.body | gsub("(?s)(\\x60{3}|~{3}).*?\\1"; "")) | test(
      "(?i)(?<!\\w)(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):?[ \t]+#\($n)(?![0-9])"))'
```

Emits `true` when at least one open PR closes `#<N>`, `false` otherwise. The **closing keyword is
the authoritative signal**, not the head-branch name: the `pr-issue-linkage` pre-create gate
guarantees a standard-flow PR carries a `Closes #<N>` keyword, so keyword-matching catches it,
while an intentional opt-out (`Refs #<num>` / `No related issue:`) correctly does NOT match and so
does not exclude its issue. This is the same keyword set the "PR closing-keyword mechanics" section
matches. Three guards keep the match precise: the leading `gsub` strips fenced code blocks
(triple-backtick or `~~~`) before matching, so a `Closes #<N>` shown only inside an example snippet
does not spuriously exclude the issue — GitHub treats fenced blocks as inert, so such a snippet
never auto-closes anything; the `(?<!\w)` lookbehind (Oniguruma, variable-width — valid in `jq`'s
regex engine) stops a keyword matching inside a longer word, so a body reading `prefixes #<N>` /
`suffix #<N>` does not spuriously exclude the issue; the trailing `(?![0-9])` number boundary keeps
`#463` from matching `#4630` / `#1463` (the `#` anchor already prevents a match inside `#1463`).

## Aggregate / count (dashboard + hygiene)

`gh issue list --json ... --jq` projections for `stats` and `audit` (bare `gh`).

Category counts:

```bash
gh issue list --state open --json labels --limit 500 --jq '
  [.[].labels[].name] | map(select(startswith("category:"))) | group_by(.) | map({key: .[0], count: length}) | sort_by(.key)
' | tr -d '\r'
```

Claimed/unassigned counts — a seam claim is an **assignee** (+ lease), so count assignees, NOT
the retired `status:claimed`/`status:considering` labels (which the seam never sets):

```bash
gh issue list --state open --json assignees --limit 500 --jq '
  { total: length,
    claimed: [.[] | select(.assignees | length > 0)] | length,
    unassigned: [.[] | select(.assignees | length == 0)] | length }
' | tr -d '\r'
```

Unlabeled (missing `type:`/`category:`) and priority-conflict projections:

```bash
gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(
    (any(.labels[]; .name | startswith("type:")) | not) or
    (any(.labels[]; .name | startswith("category:")) | not)
  ) | {number, title, labels: [.labels[].name]}]
' | tr -d '\r'

gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(([.labels[].name | select(startswith("priority:"))] | length) > 1)
       | {number, title, priorities: [.labels[] | .name | select(startswith("priority:"))]}]
' | tr -d '\r'
```

Stale-claim detection is NOT a label/date query — a claim is a lease, so the `audit` action
runs the seam `reclaim` verb over assigned items (CONTRACT.md "Lease protocol").

## Gotchas

Per-operation gotchas live with their sections above (the `--limit` truncation under "List
items", the `--add-label`-vs-`--label` rule under "Edit labels / assignees"). Cross-cutting:

- **Windows `\r`.** Git Bash adds `\r` to `gh` output through `jq`/`--jq`; end every parsing
  pipeline with `| tr -d '\r'`.
- **Rate limits** (verify current values via GitHub REST docs): batch bulk creates to respect
  the secondary content-generation limit — e.g. 30 items per batch with short pauses.
- **Issue Forms auto-labeling** fires only on web-form creation, not `gh issue create` — apply
  labels explicitly when creating programmatically.
