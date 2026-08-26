# GitHub adapter — operations reference

## Contents

- [Available `--json` fields](#available---json-fields)
- [Resolve item ID](#resolve-item-id)
- [List items](#list-items)
- [Search items](#search-items)
- [View item](#view-item)
- [List item comments](#list-item-comments)
- [Close item](#close-item)
- [Edit labels / assignees](#edit-labels--assignees)
- [Comment on item / edit a comment](#comment-on-item--edit-a-comment)
- [PR closing-keyword mechanics](#pr-closing-keyword-mechanics)
- [Open linked PRs](#open-linked-prs)
- [Aggregate / count (dashboard + hygiene)](#aggregate--count-dashboard--hygiene)
- [Gotchas](#gotchas)

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

`gh repo view --json` is GraphQL-backed, so it 403s in a sandboxed session for the reason given
under "View item" below. The REST form produces the same string:

```bash
PREFIX="$(gh api "repos/{owner}/{repo}" --jq '"github:" + .full_name' | tr -d '\r')"
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

**Sandboxed sessions: read the item over REST.** `gh issue view --json` routes through GitHub's
GraphQL API, so every `gh issue view --json` read in this document fails with `HTTP 403` wherever
only a pinned set of GraphQL operations is served (Claude Code on the web and remote execution) —
the same restriction the lease protocol's assignee ops work around under "Edit labels /
assignees" below. That 403 reads like an expired token or a missing scope and is neither, so take
it as a signal to switch APIs rather than to re-authenticate. The REST issues endpoint carries
the same fields under the same names. Use the object-array form when substituting
the general `gh issue view --json number,title,body,labels,assignees,comments`
shape (`.labels[].name` / `.assignees[].login` keep working). REST `comments` is
an integer count, not the comment list `--json comments` returns; take comments
from the paginated "List item comments" recipe.

```bash
gh api "repos/{owner}/{repo}/issues/<N>" \
  --jq '{number, title, body, labels, assignees}' \
  | tr -d '\r'
```

The already-normalized claim-precheck projection is the same filter on REST:

```bash
gh api "repos/{owner}/{repo}/issues/<N>" \
  --jq '{assignees: [.assignees[].login], labels: [.labels[].name]}' \
  | tr -d '\r'
```

`gh api` has no `--repo` flag: `{owner}` and `{repo}` expand from the repository of the current
directory, or from `GH_REPO`. Run it from the target clone, or prefix `GH_REPO=<owner>/<repo>`.

`comments` is the one projected field that does not carry over — REST returns it as an integer
count, not the list `--json comments` gives. Take comments from "List item comments" below, which
is already REST and paginates for the reason documented there.

**What this substitute does not cover.** The list, search, and aggregate projections below run on
`gh issue list --json`, which posts to `/graphql` like the reads above and carries no REST form
here. Under this restriction they are unavailable, as are the seam verbs named at the end of
"Edit labels / assignees".

## List item comments

List an item's comments (bare `gh`):

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<N>/comments?per_page=100" \
  | jq -s '[.[][] | {id, user: .user.login, created_at, body}] | sort_by(.id)' | tr -d '\r'
```

`--paginate` is load-bearing. The endpoint returns 30 per page oldest-first and reports nothing
when it truncates, so an unpaginated read silently drops the newest comments — and this repo
already has long-running telemetry items past that count.

The reduction is slurped rather than passed to `--jq` because `gh` applies `--jq` to each page
separately: `sort_by` there emits one separately-sorted array per page, never one sorted list.
`jq -s` collects the pages first, and `.[][]` flattens them.

## Close item

Close an item (WRITE — see the identity note above):

```bash
gh issue close <N> --comment "<closing note>" --reason completed
```

The `done` action closes with `--reason completed` (or `not planned` for `--not-planned`) — the
values GitHub's issue-close accepts. `--reason "not planned"` needs the quoted space.

**Duplicate close — native `--duplicate-of`.** GitHub closes a duplicate natively: this sets close
reason `duplicate` and a structured, API-queryable `duplicateOf` relationship — strictly better than
grepping a body header. `<M>` may be an issue number or URL:

```bash
gh issue close <N> --duplicate-of <M> --comment "Duplicate of #<M>"
```

**Fallback — not-planned + body-append.** For a **cross-repo** duplicate target the native
relationship is not confirmed to apply — if the native close is rejected, fall back to this; it is
also the portable shape for providers/adapters without a native duplicate reason. A superseded item
uses the same not-planned close. Append a queryable `## Duplicate of <M>` section to the body first
(`<M>` is `#<M>` same-repo, or the qualified `<owner>/<repo>#<M>` / issue URL cross-repo);
`--body-file` REPLACES the body, so this is a read-modify-write (same mechanic as "PR
closing-keyword mechanics" below):

```bash
# <M>: a bare #<M> for a same-repo duplicate; the full <owner>/<repo>#<M> reference (or
# the issue URL) for a cross-repo target, where a bare number would be ambiguous.
gh issue view <N> --json body --jq '.body' | tr -d '\r' > /tmp/issue-body.md
printf '%s\n\n%s\n' "$(cat /tmp/issue-body.md)" "## Duplicate of <M>" \
  | gh issue edit <N> --body-file -
gh issue close <N> --comment "Duplicate of <M>" --reason "not planned"
```

## Edit labels / assignees

Edit labels / assignees (WRITE — see the identity note above). Edits use
`--add-label`/`--remove-label` and `--add-assignee`/`--remove-assignee` (NOT `--label`, which
is `gh issue create` only):

```bash
gh issue edit <N> --add-label "<name>" --remove-label "<name>"
```

**Carve-out — claim assignment stays on the session identity:** the assignee MUST be the session
user (not a bot), so it runs on bare `gh`. Coordination claims go through the seam `claim` verb,
which owns this.

**The lease protocol's own assignee ops are REST, not `gh issue`.** `claim` and `reclaim` do not
use `gh issue edit --add-assignee` / `gh issue view --json assignees`: those route through
GitHub's GraphQL API, and sandboxed sessions (Claude Code on the web and remote execution) serve
only a pinned set of GraphQL operations, refusing the rest with HTTP 403 — which made the lease
protocol unrunnable there. They use `gh api` against `…/issues/<n>/assignees` instead, through the
`wit_read_assignees` / `wit_add_assignee` / `wit_remove_assignee` / `wit_try_remove_assignee`
helpers in `common.sh`. Those helpers take the same `read`/`write` writer argument as
`wit_run_gh`, so the carve-out above is preserved: `claim` passes `read` (bare `gh`) and resolves
`@me` to the login explicitly, because REST takes a literal login rather than the `@me` alias.

Note the two APIs differ on an unassignable user: `gh issue edit --add-assignee` failed loudly,
while REST `POST …/assignees` returns 201 and silently drops the login. `claim` therefore
re-reads the assignees and fails `4` (auth) when its own assignment did not land, rather than
reporting a held lease on an item the frontier still sees as unassigned.

Verbs beyond the lease protocol (`get-item`, `list-items`, `list-sub-items`, `list-frontier`,
`add-sub-item`, `link-blocks`) still resolve GraphQL-only fields (`issueType`, `blockedBy`,
`parent`, `subIssues`) or use `gh issue list`, so they remain unavailable under that restriction.

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
than re-picked — and, with the draft-aware reduction below, for `/work-items:work-loop`'s
drain-exit evaluation. The authoritative signal is **GitHub's own computed close-linkage**, not a text
match over the PR body: the GraphQL `Issue.closedByPullRequestsReferences` connection returns
exactly the PRs GitHub links as closing this issue — the same linkage GitHub renders in the
issue sidebar and acts on for merge-time auto-close. Keep only the `OPEN`-state nodes: a `MERGED`
PR that closed the issue already dropped it from the open frontier, and a `CLOSED` (unmerged) PR
is not in flight (bare read):

```bash
OWNER_REPO=$(gh repo view --json owner,name -q '.owner.login + " " + .name' | tr -d '\r')
open_pr_pages=$(gh api graphql --paginate \
  -f query='query($owner:String!, $repo:String!, $n:Int!, $endCursor:String) {
    repository(owner:$owner, name:$repo) {
      issue(number:$n) {
        closedByPullRequestsReferences(first:100, after:$endCursor, includeClosedPrs:false) {
          nodes { number state isDraft }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }' \
  -f owner="${OWNER_REPO% *}" -f repo="${OWNER_REPO#* }" -F n=<N> \
  --jq '[.data.repository.issue.closedByPullRequestsReferences.nodes[] | select(.state=="OPEN")] | any') \
  || { echo "open-linked-PR check failed for #<N>" >&2; exit 1; }
if printf '%s\n' "$open_pr_pages" | tr -d '\r' | grep -qx true; then echo true; else echo false; fi
```

On success emits `true` when at least one **open** PR closes `#<N>`, `false` otherwise. The query
requests `isDraft` so each consumer applies the draft policy its decision needs. The default
reduction above deliberately **counts drafts**: for the in-flight exclusion, a draft closing PR is
still work in flight, and re-picking its issue would be exactly the double-dispatch this operation
prevents. The drain-exit evaluation in `/work-items:work-loop` instead requires an open
**non-draft** closing PR — for that consumer, reduce with

```bash
--jq '[.data.repository.issue.closedByPullRequestsReferences.nodes[] | select(.state=="OPEN" and (.isDraft | not))] | any'
```

which emits `true` only when a ready (non-draft) open PR closes `#<N>`; every other note in this
section (failure semantics, pagination, `\r` handling) applies to both reductions unchanged. **On query
failure it emits no boolean and exits non-zero — a failed in-flight check is not `false`.** The
GraphQL call is captured first and its exit status checked before any reduction: if
`gh api graphql --paginate` fails (expired token, rate limit, or a network error on a later cursor
page), the snippet propagates that failure instead of letting an empty/partial result collapse to
`false`. This is **load-bearing for the caller**: `/work-items:work` treats `false` as "not in
flight → pickable", so silently converting a failed check to `false` would let it re-dispatch an
item whose in-flight state could not be confirmed — the exact double-dispatch this operation
exists to prevent. The caller must fail **closed** on a non-zero exit (keep the item out of this
cycle), never read the absent boolean as "no open PR". `-F n=<N>` passes the number as a GraphQL
`Int` (typed); `-f` passes the owner/repo strings; the `tr -d '\r'` on the captured output follows
the Windows/Git Bash rule under "Gotchas" (each page's boolean can otherwise arrive as `true\r`,
which `grep -qx true` would then fail to match).
The `select(.state=="OPEN")` filter is **load-bearing, not redundant with `includeClosedPrs:false`**:
that argument suppresses only `CLOSED` (unmerged) PRs, so a `MERGED` PR still appears in the
connection and must be dropped here — otherwise an issue whose only closing PR merged to a
non-default base (or that was reopened after a merge) would be wrongly reported as in-flight.
`first:100` requests the connection's maximum page (GitHub GraphQL caps `first`/`last` at 100).
Because the connection retains `MERGED` nodes, this bound counts every PR the issue has *ever*
linked as closing — not only the open ones — so a long merge/reopen history can push the
currently-open PR onto a later page. `--paginate` therefore walks the connection page by page via
`pageInfo { hasNextPage endCursor }` and the `$endCursor` variable until GitHub reports no further
pages, the GraphQL analogue of the `--limit` note under "List items"; a single-page `first:100`
read would miss an `OPEN` closing PR sorted past the first 100 nodes and wrongly report the item
pickable. `gh` applies `--jq` per page, so each page emits its own `true`/`false`; after the
exit-status guard confirms every page was fetched, `grep -qx true` collapses the captured booleans
to one result — `true` when any page carried an `OPEN` node, `false` once every page was exhausted
without one. Capturing the full stream first (rather than piping `gh` straight into `grep`) is what
lets the exit status be checked: in a bare pipeline `gh`'s non-zero exit is masked by `grep`, so a
mid-pagination failure would reduce to a spurious `false`. Why GitHub's computed
linkage instead of a body regex over `gh pr list --search`:

- **Fenced code blocks and HTML comments are inert for free.** GitHub does not link a closing
  keyword that appears only inside a fenced code block or an HTML comment, so an example snippet
  such as a fenced `Closes #<N>` never surfaces here and never spuriously excludes the still-open
  issue. There is no fence-tracking heuristic to maintain — the retired approach hand-rolled a
  `jq` `gsub` that recognized only exactly-three backticks or tildes and silently missed
  four-or-more-backtick and indented fences. This closes the fence-blindness the prior regex
  carried.
- **No word-boundary or number-boundary guards.** `#463` cannot collide with `#4630` / `#1463`
  and a keyword cannot match inside a longer word, because the reference is GitHub's parsed issue
  linkage, not a regex over raw text.
- **Base-branch correctness (behavior change).** GitHub forms the close-link only for a PR that
  targets the repository's default branch — a closing keyword on any other base branch is ignored
  and creates no linkage. This mechanic therefore does not exclude an issue whose only `Closes
  #<N>` lives on a non-default-base PR, whereas the retired raw-body regex counted it. That issue
  now stays pickable, matching GitHub's real merge-time auto-close semantics.
- **Opt-out is intrinsic.** An intentional `Refs #<num>` (reference without closing) never enters
  the closing linkage, so it correctly does not exclude its issue — the same opt-out the
  `pr-issue-linkage` gate honors, now with no keyword allow/deny list to keep in sync.

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
- **Keep body edits inside the UTF-8-safe pipeline; force UTF-8 anywhere they leave it.**
  `--json`/`--jq`, `gh api`, the bash `>` redirect, and `--body-file` pass the encoding through
  untouched, so the read-modify-write shapes above never transcode. That is an encoding guarantee,
  not a byte-for-byte one: the shapes above normalize line endings and trailing whitespace on
  purpose (`tr -d '\r'` drops CRs; `$(cat …)` strips trailing newlines, and the `printf '%s\n'`
  puts exactly one back). Corruption enters when an **ad-hoc** step decodes
  those bytes with a tool whose default is a legacy code page: the body's UTF-8 is read as Windows
  ANSI and re-encoded, putting every non-ASCII character at risk — the observed case is em-dash
  U+2014 arriving back as U+00E2 U+20AC U+201D — and that corrupted copy is then written over the
  good one. Nothing reports it; every command still exits 0. Two Windows defaults decode this way:
  Python's `open()` with no `encoding=` (the locale encoding, i.e. the ANSI code page —
  [PEP 686](https://peps.python.org/pep-0686/) makes UTF-8 the default only in 3.15+) and Windows
  PowerShell 5.1's `Get-Content` (PowerShell 6+ already defaults to `utf8NoBOM`). Do not reason
  from the version you happen to be on — state the encoding on both sides of any ad-hoc step,
  read *and* write. Python reads with `open(path, encoding='utf-8')` or
  `open(path, 'rb').read().decode('utf-8')` and writes back with
  `open(path, 'w', encoding='utf-8')` (or run under `PYTHONUTF8=1`, which covers both sides).
  Windows PowerShell 5.1 reads with `Get-Content -Raw -Encoding utf8` — without `-Raw` you get a
  line array, not the one string the write below takes — and writes back with
  `[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`, because there
  `-Encoding utf8` prepends a BOM and `utf8NoBOM` does not exist (PowerShell 6+ has both).
- **Rate limits** (verify current values via GitHub REST docs): batch bulk creates to respect
  the secondary content-generation limit — e.g. 30 items per batch with short pauses.
- **Issue Forms auto-labeling** fires only on web-form creation, not `gh issue create` — apply
  labels explicitly when creating programmatically.
