---
description: "Operator's read-only morning view of the current GitHub repo in one pass: open counts per queue label, merge-ready PRs, parked decisions with their RECOMMENDED lines, and loop-lane telemetry freshness; never mutates issues, PRs, labels, or comments. Use when: 'morning brief', 'ops dashboard', 'what needs attention', 'daily standup view'."
argument-hint: "[--repo owner/name] [--telemetry-issue N] [--queue-labels A,B,C] [--stale-hours N] [--pr-limit N]"
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/morning-brief.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/morning-brief.sh\":*)"]
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Print the operator's read-only morning view. Queues, merge-ready PRs, parked decisions
  cadence: daily
---

**Arguments.** `[--repo owner/name] [--telemetry-issue N] [--queue-labels A,B,C] [--stale-hours N] [--pr-limit N]`. Full form: [--repo owner/name] [--telemetry-issue N] [--queue-labels A,B,C] [--decision-label L] [--stale-hours N] [--stranded-days N] [--pr-limit N]. Read-only on GitHub; omit to view the current repo

## Pre-computed context

Repo: !`gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*github\.com[:/]##' | grep -E '^[^/]+/[^/]+$' || echo "unknown (run inside a checkout with a GitHub origin remote, or pass --repo)"`
gh: !`command -v gh >/dev/null 2>&1 && echo "present" || echo "MISSING (required)"`
jq: !`command -v jq >/dev/null 2>&1 && echo "present" || echo "MISSING (required)"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

The 30-60 minute operator morning pass begins with the same hand-run `gh` queries
every day. This skill collapses them into a single 5-second picture for the current
repo, so the pass starts from a complete view instead of ad-hoc lookups.

**Read-only and `gh`-based.** It runs only `gh` read queries and never mutates
labels, comments, issues, or PRs. Its one local write is the stranded-findings
bookmark under the plugin data dir. Owner/repo is derived from `gh repo view`, or
from the checkout's `origin` remote when that call is unavailable (never
hardcoded), so it is reusable across repos.

## Run it

```bash
"${CLAUDE_SKILL_DIR}/scripts/morning-brief.sh" --data-dir "${CLAUDE_PLUGIN_DATA}" $ARGUMENTS
```

Print the script's output verbatim; do not re-query the sections by hand.

Pass the data dir on the command line: the script cannot read it from its
environment under the Bash tool.

- **Pointer**: <https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>
- **As of**: 2026-10-11
- **Recheck trigger**: that section starts exporting the plugin path variables to commands run
  through the Bash tool.

When the header reports unreadable sections, say which were lost and why (each
`UNREADABLE:` line carries the cause), name the remedy the cause calls for, and
stop. A repo that could not be resolved (exit 4) wants a checkout with a GitHub
`origin` remote or `--repo`; a GraphQL refusal from the cloud GitHub proxy wants a
run from a host that serves `gh`'s GraphQL (the REST-served sections already carry
what this host can read); an authentication error wants `gh auth status`; a rate
limit or a 5xx wants a re-run after the window the error names. Never rebuild a
section from other tools.

## Status report page

Genre: reports and status. In an interactive session, read [context/view.md](context/view.md) before
running the script: it resolves the `medium` key and, when a page is wanted, has you save the same
output the reader sees and build a collapsible, filterable page from it. The printed brief is the
record; the page is a view of it. The brief holds issue and pull-request titles (K2), so only
`scripts/build-brief-view.mjs` writes the page, from its checked-in template (`templates/brief.html`) and the lines as escaped
JSON data. Never hand-write the page or add script to it. A scheduled run, CI, or `medium: terminal`
prints the brief only. `context/view.md` writes this skill's directory as `<skill-dir>`, which is
`${CLAUDE_SKILL_DIR}`, and the plugin data dir as `<plugin-data>`, which is `${CLAUDE_PLUGIN_DATA}`;
put those paths in place of the placeholders before running a command.

## Degraded sections

Every section is in one of three states: data, empty, or `UNREADABLE`. A section
whose data source failed (a non-zero `gh` exit, or an error document in the body)
renders as `UNREADABLE` with the error's first line, never as "none", "not found",
or "clear"; so does a response the script cannot parse. The header counts the
unreadable sections. Exit 5: every section unreadable, no data; 6: rendered with at
least one section unreadable; 0: every section read.

A list read that reaches its result cap prints a `PARTIAL` line in its section: the
label inventory (and then the queue rows are not filtered to labels that exist), a
queue count (shown as `N+`), the open-PR list, the decision list, and the telemetry
issue search.

When a GraphQL read is refused (the cloud GitHub proxy's HTTP 403), sections 1-4 are
re-read from repository-scoped REST endpoints and the header names the transport.
Then the merge-ready list reports `review=n/a` and reads merge state for at most
`--pr-limit` open PRs (default 50), saying so when capped or when GitHub has not
finished computing a PR's mergeability; and the stranded-findings section renders
`UNREADABLE`, because review threads have no REST read.

The brief treats a clean PR as verified only when its head contains its base branch's tip. It
reads one comparison per clean PR, up to `--pr-limit`, and prints an `UNVERIFIED` line under a PR
whose head is behind its base, whose comparison failed, or that fell past the cap; a capped read
also prints `PARTIAL`.

- **Pointer**: for what `behind_by` counts, see
  <https://docs.github.com/en/rest/commits/commits#compare-two-commits>. For when GitHub
  regenerates a PR's test merge commit, no docs page covers it as of the date; correlate with
  <https://github.blog/changelog/2026-02-19-changes-to-test-merge-commit-generation-for-pull-requests>.
- **As of**: 2026-10-02
- **Recheck trigger**: a docs page starts to cover test merge commit regeneration, or the
  `mergeStateStatus` enum gains or drops a value.

Upstream facts the script restates, each with its verification record:

- **The refusal shape the script keys the transport switch on.** Pointer:
  [Configure cloud environments § GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy),
  which gives the opening words of the proxy's GraphQL 403. As-of: 2026-10-11. The
  switch is runtime detection, so a host that never sends this shape never switches.
  Recheck trigger: that section changes its GraphQL entry, or a cloud session refuses
  a GraphQL query with a different message.
- **The REST pull schema carries no review-decision field, so the REST path reports
  `n/a`.** Basis: the "Get a pull request" response schema at
  <https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request>, which lists
  `requested_reviewers` and `review_comments` and no `review_decision`. `reviewDecision`
  and `mergeStateStatus` are `gh pr list --json` fields (gh 2.98.0 lists them
  client-side). **Pointer**: when the REST path reports a review decision, fetch
  <https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request> live. **As of**:
  2026-09-10. **Recheck trigger**: the REST pull schema gains a review-decision field,
  or gh drops either `--json` field.
- **The REST path retries a null `mergeable` read instead of treating null as the
  final answer.** **Pointer**: when that retry runs, fetch
  <https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request> live. **As of**:
  2026-10-03. **Recheck trigger**: that page changes the description of `mergeable`
  or removes the field.

## What each section reports

| Section | Source | Notes |
|---|---|---|
| Queues | `gh issue list --label <queue>` counts | Defaults to melodic-software queue labels; live runs filter to labels that exist in the repo (pass `--queue-labels` to pin a custom set) |
| Merge-ready PRs | `gh pr list` filtered to non-draft + `mergeStateStatus=CLEAN` (REST: `pulls` list plus one read per PR for `mergeable_state`) | A light glance signal; `reviewDecision` shown but not required (repos without required review leave it empty; the REST path reports `n/a`). One compare read per clean PR, capped at `--pr-limit`; `UNVERIFIED` marks a head behind its base, a comparison that could not be read, or a PR past the cap |
| Parked decisions | open issues with the decision label (default `status: needs-decision`) | Surfaces each one's RECOMMENDED line, the uppercase marker wins over an incidental lowercase mention; a case-insensitive fallback catches lowercase markers; pass `--decision-label` to pin |
| Lane telemetry | the loop-lane telemetry issue's per-lane comments | Each lane's `last-cycle` age (marked `STALE` past `--stale-hours`, default 6) and any `flags:` |
| Stranded findings | merged PRs whose unresolved review threads were **created after the merge** | One line per PR at its worst severity, with a finding count. The header prints the window: merges since the older of `--stranded-days` ago (default 3) and the repo's bookmark. Paging stops at that cutoff |

The bookmark is one file per repo under the plugin data dir. After a full read of the section it
moves to this run's `--stranded-days` floor; a failed or partial read leaves it where it was. A
merge therefore leaves the window only after a full read covered it and it fell behind that run's
floor, however long the gap between runs.

A review that lands after a merge has nowhere to go: the ruleset's
`required_review_thread_resolution` is a merge-time predicate that already passed, the babysit lane
works *open* PRs, and nothing on a merged PR surfaces its open threads. This section is the only
place they appear. The comment-vs-merge timestamp comparison is the discriminator, a thread
that predates the merge was visible to the gate and is an ordinary unresolved thread, not this
failure mode.

The telemetry issue is auto-discovered by title; pass `--telemetry-issue N` to pin it.
When no such issue exists (e.g. a consuming repo without loop-lane telemetry), that
section reports "no telemetry issue found" and the rest of the brief still renders.
A search that could not run is a different state: the section is `UNREADABLE`.

Queue labels default to the melodic-software taxonomy and are filtered to labels
that actually exist in the target repo on live runs, so a consuming repo with a
different scheme does not show misleading `0`/`?` rows. Pass `--queue-labels` to
pin a custom comma-separated set; pass `--decision-label` to pin the parked-decision
label. When none of the configured queue labels exist, the Queues section reports
"no queue labels found" and the rest of the brief still renders.

## Cross-references

- `/source-control:babysit-prs`, the **authoritative** PR merge gate and readiness
  classification. The merge-ready list here is a fast gh-native glance, not a
  substitute for that skill's per-PR gate.
- `/harness-ops:observability`. Reads locally captured telemetry (OTEL store, hook-event JSONL,
  ccusage). This skill instead reads GitHub-side queue and PR state.

## What this skill does NOT do

- **Does not mutate anything**. No label, comment, merge, or close writes.
- **Does not classify PR merge-readiness authoritatively**. Invoke `/source-control:babysit-prs`
  via the Skill tool.
- **Does not read local telemetry stores**. Invoke `/harness-ops:observability` via the Skill tool.
