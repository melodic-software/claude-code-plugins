---
description: "Prints the operator's read-only morning view for the current GitHub repo in one pass. Open counts per queue label (needs-triage / ready / needs-decision / needs-human), the gh-native merge-ready PR list, parked decisions with their RECOMMENDED lines, and loop-lane telemetry freshness (last-cycle age + flags). Use when: 'morning brief', 'morning view', 'ops dashboard', 'what needs attention', 'daily standup view', 'operator morning pass', 'queues and merge-ready'. Read-only and gh-based, never mutates issues, PRs, labels, or comments."
argument-hint: "[--repo owner/name] [--telemetry-issue N] [--queue-labels A,B,C] [--decision-label L] [--stale-hours N] [--pr-limit N]. Read-only; omit to view the current repo"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Print the operator's read-only morning view. Queues, merge-ready PRs, parked decisions
  cadence: daily
---

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
labels, comments, issues, or PRs. Owner/repo is derived from `gh repo view`, or
from the checkout's `origin` remote when that call is unavailable (never
hardcoded), so it is reusable across repos.

## Run it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/morning-brief/scripts/morning-brief.sh" $ARGUMENTS
```

Print the script's output verbatim. It is already the deliverable. Do not
re-query the sections by hand.

When the header reports unreadable sections, say which sections were lost and why
(each `UNREADABLE:` line carries the cause), name the remedy the cause calls for, and
stop. The remedy follows the cause, never a fixed line: a repo that could not be
resolved (exit 4) wants a checkout with a GitHub `origin` remote or `--repo`; a
GraphQL refusal ("not enabled for this session") wants a run from a host that serves
`gh`'s GraphQL, and the REST-served sections already carry what this host can read;
an authentication error wants `gh auth status`; a rate limit or a 5xx wants a re-run
after the window the error names. A section rebuilt from other tools is not the
brief: it costs a slow, unverified pass and its shape differs run to run.

## Degraded sections

Every section is in one of three states: data, empty, or `UNREADABLE`. A section
whose data source failed (a non-zero `gh` exit, or an error document in the body)
renders as `UNREADABLE` with the error's first line, never as "none", "not found",
or "clear". The header counts the unreadable sections, so "nothing to report" and
"could not read" are never confused. Exit code 5 means every section was
unreadable and the brief carries no data; a partial brief exits 0.

The `gh` subcommands ride GraphQL. When the host serves only a pinned set of
GraphQL operations (an HTTP 403 saying the query is "not enabled for this
session"), sections 1-4 are re-read from repository-scoped REST endpoints and the
header names the transport. Two consequences: the merge-ready list reports
`review=n/a` and reads merge state for at most `--pr-limit` open PRs (default 50),
saying so when capped or when GitHub has not finished computing a PR's mergeability;
and the stranded-findings section renders `UNREADABLE`, because review threads have
no REST read. That section never renders an all-clear it did not read.

Two upstream facts the script restates, each with its verification record:

- **The refusal shape the script keys the transport switch on.** Basis: the body
  `gh api graphql` returned in a Claude Code cloud session, `{"message":"This GraphQL
  query is not enabled for this session ... only the pinned set of PR-review operations
  is served. ..."}` with HTTP 403, whose `documentation_url` points at
  <https://docs.anthropic.com/en/docs/claude-code/github-actions>. Observed 2026-09-08
  and again 2026-09-10 in that session. The switch is runtime detection, so a host
  that never sends this shape never switches. Recheck when a cloud session refuses
  a GraphQL query with a different message, or that page names the served GraphQL set.
- **The REST pull schema carries no review-decision field, so the REST path reports
  `n/a`.** Basis: the "Get a pull request" response schema at
  <https://docs.github.com/en/rest/pulls/pulls#get-a-pull-request>, which lists
  `requested_reviewers` and `review_comments` and no `review_decision`; the same page
  says of `mergeable` that "If the value is null, then GitHub has started a background
  job to compute the mergeability. After giving the job time to complete, resubmit
  the request", which is the retry the script performs. `reviewDecision` and
  `mergeStateStatus` are `gh pr list --json` fields (gh 2.98.0 lists them client-side).
  Verified 2026-09-10 against that page as fetched that day. Recheck when the REST
  pull schema gains a review-decision field, or gh drops either `--json` field.

## What each section reports

| Section | Source | Notes |
|---|---|---|
| Queues | `gh issue list --label <queue>` counts | Defaults to melodic-software queue labels; live runs filter to labels that exist in the repo (pass `--queue-labels` to pin a custom set) |
| Merge-ready PRs | `gh pr list` filtered to non-draft + `mergeStateStatus=CLEAN` (REST: `pulls` list plus one read per PR for `mergeable_state`) | A light glance signal; `reviewDecision` shown but not required (repos without required review leave it empty; the REST path reports `n/a`) |
| Parked decisions | open issues with the decision label (default `status: needs-decision`) | Surfaces each one's RECOMMENDED line, the uppercase marker wins over an incidental lowercase mention; a case-insensitive fallback catches lowercase markers; pass `--decision-label` to pin |
| Lane telemetry | the loop-lane telemetry issue's per-lane comments | Each lane's `last-cycle` age (marked `STALE` past `--stale-hours`, default 6) and any `flags:` |
| Stranded findings | merged PRs whose unresolved review threads were **created after the merge** | One line per PR at its worst severity, with a finding count; window is `--stranded-days`, default 3 |

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
- `/claude-ops:observability`. Reads locally captured telemetry (OTEL store, hook-event JSONL,
  ccusage). This skill instead reads GitHub-side queue and PR state.

## What this skill does NOT do

- **Does not mutate anything**. No label, comment, merge, or close writes.
- **Does not classify PR merge-readiness authoritatively**. Invoke `/source-control:babysit-prs`
  via the Skill tool.
- **Does not read local telemetry stores**. Invoke `/claude-ops:observability` via the Skill tool.
