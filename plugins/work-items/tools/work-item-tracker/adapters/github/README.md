# GitHub adapter operations reference

## Contents

- [Available `--json` fields](#available---json-fields)
- [Resolve item ID](#resolve-item-id)
- [List items](#list-items)
- [Search items](#search-items)
- [List pull requests](#list-pull-requests)
- [View item](#view-item)
- [List item comments](#list-item-comments)
- [Close item](#close-item)
- [Edit labels / assignees](#edit-labels--assignees)
- [Edit title / body](#edit-title--body)
- [List labels](#list-labels)
- [Comment on item / edit a comment](#comment-on-item--edit-a-comment)
- [PR closing-keyword mechanics](#pr-closing-keyword-mechanics)
- [Open linked PRs](#open-linked-prs)
- [Label-removal provenance](#label-removal-provenance)
- [Linked changes](#linked-changes)
- [Aggregate / count (dashboard + hygiene)](#aggregate--count-dashboard--hygiene)
- [API budget](#api-budget)
- [Work status trust](#work-status-trust)
- [Gotchas](#gotchas)

Concrete `gh` mechanics for the `/work-items` skill's **non-coordination** operations against
the GitHub provider. Coordination (create / claim / lease / link / frontier) runs through the
seam verbs (`work-item-tracker.sh <verb>`, see `../../CONTRACT.md`); the operations below have
no core verb by design: listing with arbitrary filters, search, aggregation, close, and label/comment
edits carry provider-specific search/filter syntax the seam contract keeps out of core, so the skill
core describes them neutrally and resolves the mechanics here.

The commands below are standard GitHub CLI (`gh`); each layers only the work-items-specific
`--json`/`--jq` projection on top. **Identity (writes):** reads use bare `gh`; writes (close,
label/comment edits, PR-body edits) route through an optional bot wrapper when the consuming repo
provides one and fall back to bare `gh` otherwise (seam identity routing: `../../CONTRACT.md`
"Identity routing (GitHub adapter)"). The examples show bare `gh`; substitute your repo's bot
wrapper for write ops if it uses one. Claim assignment always stays on bare `gh` (`@me` must be the
session identity). Every pipeline parsing `gh` JSON on Windows/Git Bash ends with `| tr -d '\r'`
(see "Gotchas"). `<owner>/<repo>` in an issue recipe is the item's own repository, taken from its
qualified ID (the current repository for a bare number), so a cross-repository item is never confused with the current checkout's item of
the same number.

## Available `--json` fields

Do NOT hardcode the field set. GitHub adds fields over time (the dependency/parent/sub-item
fields the seam's normalized model reads, `blockedBy`, `parent`, and `subIssues`, are recent
additions). Derive the current valid set on demand: `gh issue list --json` (no value) prints it.

## Resolve item ID

Seam verbs (`get-item`, `claim`, `reclaim`, `link-blocks`, `add-sub-item`) take a
fully-qualified ID (`github:<owner>/<repo>#<N>`, CONTRACT.md "ID grammar"); a bare `#N` is
rejected. The **seam** verbs (`list-frontier`, `get-item`, `create-item`) already emit the
qualified `id`, so pass it straight through. The adapter's raw `list` / `search` projections below
emit only `number`, so build the qualified ID from the number:

```bash
PREFIX="$(gh repo view --json owner,name -q '"github:\(.owner.login)/\(.name)"' | tr -d '\r')"
ID="${PREFIX}#<N>"
```

In a sandboxed session use the REST form, which produces the same string (the pointer under
"View item" below says which requests those sessions refuse):

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
`--assignee "@me"` for the current user). Always pass `--limit` sized to the rows needed; the
default cap is read at [gh issue list § Options](https://cli.github.com/manual/gh_issue_list#options). Past what one
`--limit` returns, page with `--search` date ranges.

**Recurring items with their marker.** The recurring flows match an item to its schedule row by a
body line ([`../../../../reference/issue-conventions.md`](../../../../reference/issue-conventions.md)
"Recurring marker"), so their read adds `body` to the `--json` fields above, with `--label` set
to the resolved `recurring-maintenance` label.

**`list-items` in a cloud session.** `gh issue list --json blockedBy` is GraphQL, so with
`CLAUDE_CODE_REMOTE=true` the `list-items` verb reads the
[repository issues endpoint](https://docs.github.com/en/rest/issues/issues#list-repository-issues)
instead: 100 rows a page, pull requests dropped, `--label` sent as the `labels` parameter (a label
containing a comma lists unfiltered and the core's exact match filters it). Each row's
`issue_dependencies_summary.total_blocked_by` says whether it has blockers; only a row with any,
or with no summary, costs one
[`dependencies/blocked_by`](https://docs.github.com/en/rest/issues/issue-dependencies) read, whose
issue objects carry the `state`, `state_reason` and labels the blocker counts need. `parent_id` is
null on both paths, since neither list read fetches the parent.

## Search items

Search with `--search` (GitHub search syntax, not `gh` flags):

```bash
gh issue list --search "<query>" --state open   --json number,title,state,labels,assignees --limit 20 | tr -d '\r'
gh issue list --search "<query>" --state closed --json number,title,state,labels,closedAt   --limit 10 | tr -d '\r'
```

A typical query: `label:type:chore label:recurring no:assignee sort:created-asc`. The qualifiers
are read live at GitHub's searching issues and pull requests page, one section each:
[§ Search by label](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-label),
[§ Search by assignee](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-assignee),
[§ Search by missing metadata](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-missing-metadata),
[§ Search by the title, body, or comments](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-the-title-body-or-comments)
and
[§ Search by when an issue or pull request was created or last updated](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests#search-by-when-an-issue-or-pull-request-was-created-or-last-updated). That page leaves
`sort:` to GitHub's sorting search results page, linked from its "Further reading".

**REST form (cloud sessions).** A cloud session searches with neither `gh issue list --search` nor
REST `search/issues`. List the
repo's issues over REST and filter client-side: `<terms>` are the query words, all of which must
appear in the title, case-insensitively. Pull requests come back from the issues endpoint and are
dropped.

<!-- rest-search-filter:start -->
```bash
FILTER='.[] | select(.pull_request | not) | select((.title | ascii_downcase) as $t | $q | ascii_downcase | split(" ") | map(select(. != "")) | all(. as $w | $t | contains($w))) | [.number, .title, .state] | @tsv'
gh api --paginate 'repos/{owner}/{repo}/issues?state=all&per_page=100' | jq -r --arg q "<terms>" "$FILTER" | tr -d '\r'
```
<!-- rest-search-filter:end -->

## List pull requests

"List items" and `list-items` return issues only. Open pull requests carrying a label (bare `gh`):

```bash
gh pr list --label "$LABEL" --state open \
  --json number,title,state,labels,assignees,author,createdAt,url \
  --limit "${LIMIT:-100}" | tr -d '\r'
```

A pull request is an issue to the REST API, so "List item comments" and the seam's REST lease
verbs take its number unchanged. Comment with `gh pr comment <N>` and edit labels with
`gh pr edit <N>`, using the flags "Comment on item" and "Edit labels / assignees" name.

## View item

View an item (bare `gh`):

```bash
gh issue view <N> --json number,title,body,labels,assignees,comments | tr -d '\r'
# Another repository's item (a qualified ID always supplies <owner>/<repo>):
gh issue view <N> --repo <owner>/<repo> --json number,title,body,labels,state,url | tr -d '\r'
```

Assignee/label projection for claim pre-checks:

```bash
gh issue view <N> --json assignees,labels \
  --jq '{assignees: [.assignees[].login], labels: [.labels[].name]}' | tr -d '\r'
```

**Sandboxed sessions: read the item over REST.** In a cloud session (Claude Code on the web and
remote execution) read the item with the REST recipe below, not `gh issue view --json`, whose API
the GitHub proxy pointer below covers. The lease protocol's assignee ops use REST under "Edit
labels / assignees" below for the same reason, and
every other "sandboxed session" remark in this plugin cites this note. Take a 403 there as a signal
to switch APIs rather than to re-authenticate.

The adapter makes that switch itself: with `CLAUDE_CODE_REMOTE=true` (set in cloud sessions) it
takes the REST read and create paths whatever the `gh` version, and a native read or create that
fails with a 403 starting `GitHub GraphQL is not available from Claude Code sessions` is retried
over REST. `list-items`, and so `list-frontier`, reads REST there too (see "List items" above).
The adapter's sub-issue and dependency edge writes and its sub-item listing have no REST path, so
`add-sub-item`, `link-blocks`, `list-sub-items` and `create-item --parent` or `--blocked-by` exit 3
there with an "unavailable in this Claude Code cloud session" message.

- **Pointer**: when a `gh` call returns 403 in a cloud session, fetch the GraphQL restrictions in
  [cloud environments § GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy)
  live.

The REST recipe below substitutes for the general
`gh issue view --json number,title,body,labels,assignees,comments` shape (`.labels[].name` /
`.assignees[].login` keep working) except for comments: take those from the paginated "List item
comments" recipe.

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

Run `gh api` from the target clone, or prefix `GH_REPO=<owner>/<repo>`; where its `{owner}` and
`{repo}` placeholders come from is read in the description at the top of
[gh api](https://cli.github.com/manual/gh_api).

**What this substitute does not cover.** The list, search, and aggregate projections below run on
`gh issue list --json` and carry no REST form here, so a cloud session does not use them, nor the
seam verbs named at the end of "Edit labels / assignees".

## List item comments

List an item's comments (bare `gh`):

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<N>/comments?per_page=100" \
  | jq -s '[.[][] | {id, user: .user.login, created_at, body}] | sort_by(.id)' | tr -d '\r'
```

`--paginate` is required: an unpaginated read stops at the first page, and this repo already has
long-running telemetry items past one page. Page size and how a response signals further pages
are read at
[using pagination in the REST API § About pagination](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api#about-pagination).

The reduction is slurped rather than passed to `--jq` because `gh` applies `--jq` to each page
separately: `sort_by` there emits one separately-sorted array per page, never one sorted list.
`jq -s` collects the pages first, and `.[][]` flattens them.

## Close item

Close an item (WRITE, see the identity note above):

```bash
gh issue close <N> --repo <owner>/<repo> --comment "<closing note>" --reason completed
```

The `done` action closes with `--reason completed`, and with `--reason "not planned"` for
`--not-planned`. The accepted reasons are read at
[gh issue close § Options](https://cli.github.com/manual/gh_issue_close#options).

**Re-point dependents first.** The steps and their order are in
[`reference/issue-conventions.md`](../../../../reference/issue-conventions.md) "Dependents on
close"; the GitHub reads and writes they name are these. List the open items `<N>` blocks over
REST, which runs in a cloud session too and keeps the cross-repo dependents the `--json blocking`
projection drops (see "Gotchas"):

```bash
set -o pipefail
gh api --paginate "repos/<owner>/<repo>/issues/<N>/dependencies/blocking" \
  --jq '.[] | select(.state == "open") | [.number, .html_url] | @tsv' | tr -d '\r'
```

A non-zero exit means the list may be empty or partial, not that `<N>` blocks nothing: stop the
close and report it.

After the seam's `link-blocks` adds a dependent's edge to its carrier, remove its edge to `<N>`,
naming the dependent in its own repository (taken from its `html_url`):

```bash
gh issue edit <dependent> --repo <dependent-owner>/<dependent-repo> --remove-blocked-by <N-url>
```

`link-blocks` exits 3 in a cloud session ("Sandboxed sessions" under "View item"), so a close
whose dependents need a new carrier is not made there; report it for a session that can write the
edges. A close that keeps its edges (delivered, or dropped with no carrier) needs no edge write
and goes ahead.

- **Pointer**: the endpoint at
  [issue dependencies § List dependencies an issue is blocking](https://docs.github.com/en/rest/issues/issue-dependencies#list-dependencies-an-issue-is-blocking);
  the flag at [gh issue edit § Options](https://cli.github.com/manual/gh_issue_edit#options).

**Duplicate close with native `--duplicate-of`.** GitHub closes a duplicate natively: this sets close
reason `duplicate` and a structured, API-queryable `duplicateOf` relationship, strictly better than
grepping a body header. `<M>` may be an issue number or URL:

```bash
gh issue close <N> --repo <owner>/<repo> --duplicate-of <M> --comment "Duplicate of #<M>"
```

**Fallback: not-planned + body-append.** For a **cross-repo** duplicate target the native
relationship is not confirmed to apply. If the native close is rejected, fall back to this; it is
also the portable shape for providers/adapters without a native duplicate reason. A superseded item
uses the same not-planned close. Append a queryable `## Duplicate of <M>` section to the body first
(`<M>` is `#<M>` same-repo, or the qualified `<owner>/<repo>#<M>` / issue URL cross-repo);
`--body-file` REPLACES the body, so this is a read-modify-write (same mechanic as "PR
closing-keyword mechanics" below):

```bash
# <M>: a bare #<M> for a same-repo duplicate; the full <owner>/<repo>#<M> reference (or
# the issue URL) for a cross-repo target, where a bare number would be ambiguous.
gh issue view <N> --repo <owner>/<repo> --json body --jq '.body' | tr -d '\r' > /tmp/issue-body.md
printf '%s\n\n%s\n' "$(cat /tmp/issue-body.md)" "## Duplicate of <M>" \
  | gh issue edit <N> --repo <owner>/<repo> --body-file -
gh issue close <N> --repo <owner>/<repo> --comment "Duplicate of <M>" --reason "not planned"
```

## Edit labels / assignees

Edit labels / assignees (WRITE, see the identity note above). This adapter edits labels and
assignees through `gh issue edit`; its flags are read at
[gh issue edit § Options](https://cli.github.com/manual/gh_issue_edit#options):

```bash
gh issue edit <N> --repo <owner>/<repo> --add-label "<name>" --remove-label "<name>"
gh issue edit <N> --repo <owner>/<repo> --remove-assignee "@me"   # clear this session's own assignment
```

**Carve-out: claim assignment stays on the session identity.** The assignee MUST be the session
user (not a bot), so it runs on bare `gh`. Coordination claims go through the seam `claim` verb,
which owns this.

**The lease protocol's own assignee ops are REST, not `gh issue`.** `claim` and `reclaim` do not
use `gh issue edit --add-assignee` / `gh issue view --json assignees`: those route through
GitHub's GraphQL API, which made the lease protocol unrunnable in cloud sessions (see "View item"
above). They use `gh api` against `…/issues/<n>/assignees` instead, through the
`wit_read_assignees` / `wit_add_assignee` / `wit_remove_assignee` / `wit_try_remove_assignee`
helpers in `common.sh`. Those helpers take the same `read`/`write` writer argument as
`wit_run_gh`, so the carve-out above is preserved: `claim` passes `read` (bare `gh`) and resolves
`@me` to the login explicitly rather than passing the alias.

`claim` then re-reads the assignees and fails `4` (auth) when its own assignment did not land,
rather than reporting a held lease on an item the frontier still sees as unassigned. What the
endpoint does with a login it cannot assign is read at
[assignees § Add assignees to an issue](https://docs.github.com/en/rest/issues/assignees#add-assignees-to-an-issue).

Of the verbs beyond the lease protocol, `get-item`, `list-items` and `list-frontier` switch to
REST under that restriction ("View item", "List items"). `list-sub-items`, `add-sub-item` and
`link-blocks` still use GraphQL-only fields (`blockedBy`, `parent`, `subIssues`), so they remain
unavailable there.

## Edit title / body

For `/work-items:track edit` (WRITE, see the identity note above). `--body-file` REPLACES the
body, so an edit that keeps part of it reads the body first ("View item") and writes the whole
result back:

```bash
gh issue edit <N> --repo <owner>/<repo> --title "$(cat <title-file>)"   # the title travels in a file, never typed
gh issue edit <N> --repo <owner>/<repo> --body-file <path>
```

## List labels

For `/work-items:track labels` and the label checks in `add` (bare read). Always pass `--limit`;
the default cap is read at [gh label list § Options](https://cli.github.com/manual/gh_label_list#options):

```bash
gh label list --repo <owner>/<repo> --limit 1000 --json name --jq '.[].name' | tr -d '\r'
```

## Comment on item / edit a comment

Comment on an item, or edit a comment via PATCH (preserves the audit trail). Both are WRITE
operations (see the identity note above):

```bash
gh issue comment <N> --repo <owner>/<repo> --body "<text>"
gh issue comment <N> --repo <owner>/<repo> --body-file <path>   # the form `/work-items:track edit --comment-file` uses
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<CID>" -f body="<text>"
```

## PR closing-keyword mechanics

For the `done` action's belt-and-suspenders keyword check. Read the PR body (bare `gh`); the
read-modify-write body edit uses `--body-file`, which REPLACES the body (WRITE, see the identity
note above):

```bash
gh pr view <PR> --json body,mergedAt --jq '.body' | tr -d '\r' > /tmp/pr-body.md
# On an UNMERGED PR lacking a closing keyword and an opt-out marker, prepend `Closes #<N>`:
printf '%s\n\n%s\n' "Closes #<N>" "$(cat /tmp/pr-body.md)" \
  | gh pr edit <PR> --body-file -
```

The prepended line is `change-link <id> --repo <PR's owner>/<repo>`'s `closes` text (CONTRACT.md "Change links").

Match GitHub's issue-closing keyword set followed by `#<num>`, read live at
[linking a pull request to an issue § Linking a pull request to an issue using a keyword](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword); the opt-out markers
`Refs #<num>` / `No related issue:` leave the body untouched.

## Open linked PRs

For `/work-items:work` selection, report whether item `<N>` already has an open PR targeting it
for closure, so a candidate whose work is in flight is dropped from the pickable frontier rather
than re-picked. With the draft-aware reduction below, the same check serves `/work-items:work-loop`'s
drain-exit evaluation. The authoritative signal is **GitHub's own computed close-linkage**, not a text
match over the PR body, read from the GraphQL `Issue.closedByPullRequestsReferences` connection.
What that linkage covers is read at
[linking a pull request to an issue § About linked issues and pull requests](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#about-linked-issues-and-pull-requests).
Keep only the `OPEN`-state nodes whose **head branch lives in the item's own repository**: a
`MERGED` PR that closed the issue already dropped it from the open frontier, a `CLOSED` (unmerged) PR is not in flight, and a PR from a fork
(or from another repository whose body says `Closes owner/repo#<N>`) is an outsider's proposal,
not our work in flight. Counting it would let anyone park an item for the whole stale-in-flight
window by opening a PR. A fork that was deleted has a `null` head repository and is dropped too.
The reductions (bare read):

<!-- open-linked-prs-filter:start -->
```bash
PR_OPEN='.data.repository as $r | $r.issue.closedByPullRequestsReferences.nodes[] | select(.state == "OPEN" and .headRepository.nameWithOwner == $r.nameWithOwner)'
PR_GATE="[$PR_OPEN] | any"
PR_READY_GATE="[$PR_OPEN | select(.isDraft | not)] | any"
PR_REPORT="$PR_OPEN | {number, isDraft, createdAt} | tojson"
```
<!-- open-linked-prs-filter:end -->

```bash
OWNER_REPO=$(gh repo view --json owner,name -q '.owner.login + " " + .name' | tr -d '\r')
open_pr_pages=$(gh api graphql --paginate \
  -f query='query($owner:String!, $repo:String!, $n:Int!, $endCursor:String) {
    repository(owner:$owner, name:$repo) {
      nameWithOwner
      issue(number:$n) {
        closedByPullRequestsReferences(first:100, after:$endCursor, includeClosedPrs:false) {
          nodes { number state isDraft createdAt headRepository { nameWithOwner } }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }' \
  -f owner="${OWNER_REPO% *}" -f repo="${OWNER_REPO#* }" -F n=<N> \
  --jq "$PR_GATE") \
  || { echo "open-linked-PR check failed for #<N>" >&2; exit 1; }
if printf '%s\n' "$open_pr_pages" | tr -d '\r' | grep -qx true; then echo true; else echo false; fi
```

On success emits `true` when at least one **open same-repository** PR closes `#<N>`, `false`
otherwise. The query requests `isDraft` so each consumer applies the draft policy its decision
needs. `PR_GATE` deliberately **counts drafts**: for the in-flight exclusion, a draft closing PR is
still work in flight, and re-picking its issue would be exactly the double-dispatch this operation
prevents. The drain-exit evaluation in `/work-items:work-loop` instead requires an open
**non-draft** closing PR. For that consumer, pass `--jq "$PR_READY_GATE"`, which emits `true` only
when a ready (non-draft) open same-repository PR closes `#<N>`. `PR_REPORT` is for **reporting**:
it emits each such PR as one compact JSON line `{number, isDraft, createdAt}` (`createdAt` is an
ISO-8601 UTC timestamp), and nothing when none closes `#<N>`. Run it with the same
captured-then-checked call, then `printf '%s\n' "$open_pr_pages" | tr -d '\r'` in place of the
`grep -qx true` line. The two boolean reductions are for gating and this one is for
reporting: a caller never derives the gate from it, and reads an item's report fields from it only
after the boolean has already excluded the item. Every other note in this section (failure
semantics, pagination, `\r` handling) applies to all three reductions unchanged. **On query
failure it emits no boolean and exits non-zero. A failed in-flight check is not `false`.** The
GraphQL call is captured first and its exit status checked before any reduction: if
`gh api graphql --paginate` fails (expired token, rate limit, or a network error on a later cursor
page), the snippet propagates that failure instead of letting an empty/partial result collapse to
`false`. This **matters to the caller** because `/work-items:work` treats `false` as "not in
flight → pickable", so silently converting a failed check to `false` would let it re-dispatch an
item whose in-flight state could not be confirmed, the exact double-dispatch this operation
exists to prevent. The caller must fail **closed** on a non-zero exit (keep the item out of this
cycle), never read the absent boolean as "no open PR". `-F n=<N>` passes the number as a GraphQL
`Int` (typed); `-f` passes the owner/repo strings; the `tr -d '\r'` on the captured output follows
the Windows/Git Bash rule under "Gotchas" (each page's boolean can otherwise arrive as `true\r`,
which `grep -qx true` would then fail to match).
The `select(.state=="OPEN")` filter stays beside `includeClosedPrs:false`: the query output is
filtered to `OPEN` here rather than trusting the argument, so an issue whose only closing PR merged
(or that was reopened after a merge) is never reported in flight. What the argument filters is read
at the [`Issue` object reference](https://docs.github.com/en/graphql/reference/issues#issue)'s
`closedByPullRequestsReferences` field.
`first:100` requests the connection's maximum page (GitHub GraphQL caps `first`/`last` at 100).
Because the connection retains `MERGED` nodes, this bound counts every PR the issue has *ever*
linked as closing, not only the open ones, so a long merge/reopen history can push the
currently-open PR onto a later page. `--paginate` therefore walks the connection page by page via
`pageInfo { hasNextPage endCursor }` and the `$endCursor` variable until GitHub reports no further
pages, the GraphQL analogue of the `--limit` note under "List items"; a single-page `first:100`
read would miss an `OPEN` closing PR sorted past the first 100 nodes and wrongly report the item
pickable. `gh` applies `--jq` per page, so each page emits its own `true`/`false`; after the
exit-status guard confirms every page was fetched, `grep -qx true` collapses the captured booleans
to one result: `true` when any page carried an `OPEN` node, `false` once every page was exhausted
without one. Capturing the full stream first (rather than piping `gh` straight into `grep`) is what
lets the exit status be checked: in a bare pipeline `gh`'s non-zero exit is masked by `grep`, so a
mid-pagination failure would reduce to a spurious `false`. Why GitHub's computed
linkage instead of a body regex over `gh pr list --search`:

- **No fence-tracking heuristic to maintain.** Whether text in a PR body forms a link is
  GitHub's call, so an example snippet such as a fenced `Closes #<N>` is judged by GitHub, not by
  a local parser. The retired approach hand-rolled a
  `jq` `gsub` that recognized only exactly-three backticks or tildes and silently missed
  four-or-more-backtick and indented fences. This closes the fence-blindness the prior regex
  carried.
- **No word-boundary or number-boundary guards.** `#463` cannot collide with `#4630` / `#1463`
  and a keyword cannot match inside a longer word, because the reference is GitHub's parsed issue
  linkage, not a regex over raw text.
- **Base-branch correctness (behavior change).** The retired raw-body regex counted a
  `Closes #<N>` on a PR against any base branch. This mechanic counts only what GitHub links, so
  an issue whose only closing keyword sits on a PR GitHub does not link now stays pickable,
  matching GitHub's merge-time auto-close. Which base branches link, and which text in a body is
  ignored, are read at
  [§ Linking a pull request to an issue using a keyword](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword).
- **Opt-out is intrinsic.** An intentional `Refs #<num>` (reference without closing) never enters
  the closing linkage, so it correctly does not exclude its issue. That is the same opt-out the
  `pr-issue-linkage` gate honors, now with no keyword allow/deny list to keep in sync.

## Label-removal provenance

For `/work-items:work-loop`'s provenance-removal hold: who last removed label `<label>` from item
`<N>`, and the repository permission that actor holds. It is the removal-side counterpart of the
seam's `label-provenance` verb, which reads only `labeled` events, and it uses the same
permission read and the same mapping: `admin` and `write` are trusted (maintain maps to `write`),
and anything else, triage and read included, is below `write`. Two bare reads, each captured and
its exit status checked before any reduction, so a failed read is never an empty result.

**Latest removal.** The timeline paginates oldest-first, `gh` applies `--jq` per page, and the
pages are slurped before the reduction ("List item comments" above). The label name reaches `jq`
only as an `--arg` value:

<!-- label-removal-filter:start -->
```bash
REMOVALS='[.[] | select(.event == "unlabeled") | {label: (.label.name // null), actor: (.actor.login // null), at: (.created_at // "")}]'
LATEST_REMOVAL='add // [] | [.[] | select(.label == $l)] | sort_by(.at) | last // empty'
```
<!-- label-removal-filter:end -->

```bash
removals=$(gh api --paginate "repos/<owner>/<repo>/issues/<N>/timeline?per_page=100" --jq "$REMOVALS") \
  || { echo "removal read failed for #<N>" >&2; exit 1; }
printf '%s\n' "$removals" | tr -d '\r' | jq -cs --arg l "<label>" "$LATEST_REMOVAL"
```

It prints `{label, actor, at}` for the latest removal, and nothing when the label was never
removed. A row whose `actor` is `null` has no usable actor login, and the caller fails closed on it.

**Actor permission.** The login is the one value that reaches an API path, so it is checked
against GitHub's login grammar first (an app's `[bot]` form included), the same check
`label-provenance.sh` makes; a login that fails it reaches no command:

```bash
login_re='^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$'
[[ "$actor" =~ $login_re ]] || { echo "no usable actor login" >&2; exit 1; }
permission=$(gh api "repos/<owner>/<repo>/collaborators/$actor/permission" --jq '.permission // ""') \
  || { echo "permission read failed for $actor" >&2; exit 1; }
permission=$(printf '%s' "$permission" | tr -d '\r')
```

`$actor` is the `actor` field read from the removal row with `jq -r`, never typed into the
command. An empty `permission` is a permission that does not read. Both cases fail closed in the
caller, the same as a non-zero exit. The endpoint and its role mapping are cited in
`/work-items:work-loop`'s labeler precondition pointer.

## Linked changes

For `/work-items:track changes`: the PRs linked as closing item `<N>`, read from the same
`closedByPullRequestsReferences` connection as "Open linked PRs" above, so the same rules
apply: `--paginate`, `-F` for the typed `Int`, the output captured and its exit status checked
before any reduction, and `tr -d '\r'`. A failed query is not an empty result. Unlike the in-flight
check it keeps PRs from any head repository and sets `includeClosedPrs:true`, because a caller
deriving what shipped wants every state; the caller filters by `state`.
`<owner>`/`<repo>` are the item's own repository (bare read):

```bash
linked=$(gh api graphql --paginate \
  -f query='query($owner:String!, $repo:String!, $n:Int!, $endCursor:String) {
    repository(owner:$owner, name:$repo) {
      issue(number:$n) {
        closedByPullRequestsReferences(first:100, after:$endCursor, includeClosedPrs:true) {
          nodes { number url state isDraft }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }' \
  -f owner="<owner>" -f repo="<repo>" -F n=<N> \
  --jq '.data.repository.issue.closedByPullRequestsReferences.nodes[] | {number, url, state, isDraft}') \
  || { echo "linked-changes read failed for #<N>" >&2; exit 1; }
printf '%s\n' "$linked" | tr -d '\r' | jq -s '.'
```

`state` is `OPEN`, `MERGED` or `CLOSED`. A PR that only mentions the item (`Refs #<N>`) is not in
this linkage, by design (see "Open linked PRs").

## Aggregate / count (dashboard + hygiene)

`gh issue list --json ... --jq` projections for `stats` and `audit` (bare `gh`).

Category counts:

```bash
gh issue list --state open --json labels --limit 500 --jq '
  [.[].labels[].name] | map(select(startswith("category:"))) | group_by(.) | map({key: .[0], count: length}) | sort_by(.key)
' | tr -d '\r'
```

Claimed/unassigned counts. A seam claim is an **assignee** (+ lease), so count assignees, NOT
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

Stale-claim detection is NOT a label/date query. A claim is a lease, so the `audit` action
runs the seam `reclaim` verb over assigned items (CONTRACT.md "Lease protocol").

## API budget

Every `gh` call by every agent and session under one user shares that user's hourly REST and
GraphQL budgets, and `gh` never retries or backs off. Every unattended loop (work-loop, triage and
attend-queue lanes) follows this cadence:

- **Which bucket.** GraphQL: `gh issue` (every subcommand), `gh pr view`, `gh pr list`,
  `gh pr checks`, `gh pr create`, `edit`, `ready` and `merge`, `gh api graphql`. REST: `gh run`,
  `gh api <path>`.
- **Waiting.** One watcher per PR or run, in the background, polling at 60 s or longer:
  `gh run watch <id> --exit-status -i 60`, or REST reads of `repos/<owner>/<repo>/pulls/<n>` and
  `commits/<sha>/check-runs`. Never loop `gh pr view` or `gh issue view`, and never run
  `gh pr checks --watch`.
- **GraphQL-only fields** (`isInMergeQueue`, `statusCheckRollup`): read once, at the point you
  decide.
- **Writes** (label, comment, close, create, assign): one at a time, at least 1 s apart, never in
  a retry loop. `wit_write_pause` in `common.sh` waits 1 s before every adapter write, so a verb
  that writes more than once keeps the spacing.
- **Rate-limit errors** (seam exit 8 when a verb hits one). Stop at the first one; never retry in
  a loop or probe for recovery. Exit 8 carries no response headers, so read the primary resets
  once: `gh api rate_limit --jq '.resources | .core, .graphql | "\(.remaining) \(.reset)"'`. When a
  bucket shows 0 remaining, wait until its reset (epoch seconds); otherwise the limit was a secondary one
  (that endpoint does not show them), so wait at least one minute, then back off exponentially and
  give up after a few tries.

Pointer: [best practices for using the REST API](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api),
[REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
[GraphQL rate limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api).

## Work status trust

The optional binding key `config.github.status_trust` makes the `get-statuses` verb count a Work
status value only from an account the repository trusts. Decision readers built on it (the
autonomous frontier) then never act on a value an untrusted account set. Display readers that
call `gh` directly see the plain field value.

```yaml
tracker:
  config:
    github:
      status_trust:
        trusted_actors: .github/standards/trusted-actors/trusted-actors.json
        model: docs/conventions/pr-pipeline.yaml
        lanes_app: melodic-automation-lanes[bot]
```

- `trusted_actors`: a repo-relative path to the trust list, `{version: 1, actors: [{id, login,
  kind}]}`, every id a positive whole number.
- `model`: a repo-relative path to a YAML file whose `models.issue-status` block gives `field-id`,
  `options` (option id to state), and `bot-setters` (`{id, login}` entries), and may give
  `ready-state`, the state only a person's value counts for (absent or empty: `agent-ready`).
- `lanes_app`: the lanes App's login, which counts for every state while the trust list holds it.

Both files are read from each item repository's default branch. A Work status field event counts
when a listed `human` or the lanes App wrote it, for any state, or when a `bot-setters` account
wrote any state but the `ready-state`, provided it is `github-actions[bot]` (id 41898282) or the trust
list holds it as `kind: bot` with the same id and login. The newest counted event decides; a
counted removal reads null, and with no counted event the item reads null. The read takes the
newest 100 field events and 25 field values per issue.

| Exit | When |
|---|---|
| `3` | The key is malformed or a member is missing, a file is absent, the trust list is not version 1 or holds a non-positive or non-whole id, or the model's `field-id`, `options` or `bot-setters` is invalid. |
| `1` | 25 field values fill the page; the 100-event window is full, the field holds a value, and no event counts; or a counted state is one `options` does not map. |

Without the key, or with no binding, the read is the plain field value.

## Gotchas

Per-operation gotchas live with their sections above (the `--limit` rule under "List items").
Cross-cutting:

- **Windows `\r`.** Git Bash adds `\r` to `gh` output through `jq`/`--jq`; end every parsing
  pipeline with `| tr -d '\r'`.
- **Never filter `--json subIssues` nodes on `.repository`.** Derive owner/repo from the node's
  `url` (`<host>/<owner>/<repo>/issues/<n>`), or request `repository { nameWithOwner }` through
  `gh api graphql`; a filter on `.repository.nameWithOwner` reads as "no children". `parent`,
  `blockedBy` and `blocking` nodes get the same treatment, and `get-item` and `list-items` read
  closed blockers' close reasons with one `gh api graphql` `nodes(ids:)` query. Which fields
  `--json` exports is read at
  [gh issue view § JSON Fields](https://cli.github.com/manual/gh_issue_view#json-fields).
  A node the adapter can attribute to neither field is dropped and named on stderr, so
  a further narrowing of the projection surfaces as a message instead of as another silently
  empty list. A node attributed to a *different* repo is dropped silently: that one is the
  documented cross-repo truncation, not a fault.
- **Keep body edits inside the UTF-8-safe pipeline; force UTF-8 anywhere they leave it.**
  `--json`/`--jq`, `gh api`, the bash `>` redirect, and `--body-file` pass the encoding through
  untouched, so the read-modify-write shapes above never transcode. That is an encoding guarantee,
  not a byte-for-byte one: the shapes above normalize line endings and trailing whitespace on
  purpose (`tr -d '\r'` drops CRs; `$(cat …)` strips trailing newlines, and the `printf '%s\n'`
  puts exactly one back). Corruption enters when an **ad-hoc** step decodes
  those bytes with a tool whose default is a legacy code page: the body's UTF-8 is read as Windows
  ANSI and re-encoded, putting every non-ASCII character at risk, and that corrupted copy is then
  written over the good one. The observed case is em-dash U+2014 arriving back as U+00E2 U+20AC
  U+201D. Nothing reports it; every command still exits 0. Two Windows defaults decode this way:
  Python's `open()` with no `encoding=` (the locale encoding, i.e. the ANSI code page, since
  [PEP 686](https://peps.python.org/pep-0686/) makes UTF-8 the default only in 3.15+) and Windows
  PowerShell 5.1's `Get-Content` (PowerShell 6+ already defaults to `utf8NoBOM`). Do not reason
  from the version you happen to be on. State the encoding on both sides of any ad-hoc step,
  read *and* write. Python reads with `open(path, encoding='utf-8')` or
  `open(path, 'rb').read().decode('utf-8')` and writes back with
  `open(path, 'w', encoding='utf-8')` (or run under `PYTHONUTF8=1`, which covers both sides).
  Windows PowerShell 5.1 reads with `Get-Content -Raw -Encoding utf8` and writes back with
  `[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`, because there
  `-Encoding utf8` prepends a BOM and `utf8NoBOM` does not exist (PowerShell 6+ has both). Without
  `-Raw` you get a line array, not the one string that write takes.
- **Rate limits**: see [API budget](#api-budget).
- **Apply labels explicitly when creating an item programmatically**, never relying on an issue
  form's `labels` key. Which creation paths apply that key is read at
  [syntax for issue forms § Top-level syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms#top-level-syntax).
