---
name: morning-brief
description: "Prints the operator's read-only morning view for the current GitHub repo in one pass — open counts per queue label (needs-triage / ready / needs-decision / needs-human), the gh-native merge-ready PR list, parked decisions with their RECOMMENDED lines, and loop-lane telemetry freshness (last-cycle age + flags). Use when: 'morning brief', 'morning view', 'ops dashboard', 'what needs attention', 'daily standup view', 'operator morning pass', 'queues and merge-ready'. Read-only and gh-based — never mutates issues, PRs, labels, or comments."
argument-hint: "[--repo owner/name] [--telemetry-issue N] [--stale-hours N] — read-only; omit to view the current repo"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Repo: !`gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "unknown (run inside a gh repo or pass --repo)"`
gh: !`command -v gh >/dev/null 2>&1 && echo "present" || echo "MISSING (required)"`
jq: !`command -v jq >/dev/null 2>&1 && echo "present" || echo "MISSING (required)"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

The 30-60 minute operator morning pass begins with the same hand-run `gh` queries
every day. This skill collapses them into a single 5-second picture for the current
repo, so the pass starts from a complete view instead of ad-hoc lookups.

**Read-only and `gh`-based.** It runs only `gh` read queries and never mutates
labels, comments, issues, or PRs. Owner/repo is derived from `gh repo view` (never
hardcoded), so it is reusable across repos.

## Run it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/morning-brief/scripts/morning-brief.sh" $ARGUMENTS
```

Print the script's output verbatim — it is already the deliverable. Do not
re-query the sections by hand.

## What each section reports

| Section | Source | Notes |
|---|---|---|
| Queues | `gh issue list --label <queue>` counts | Labels: `priority: needs-triage`, `status: ready`, `status: needs-decision`, `needs-human` |
| Merge-ready PRs | `gh pr list` filtered to non-draft + `mergeStateStatus=CLEAN` | A light glance signal; `reviewDecision` shown but not required (repos without required review leave it empty) |
| Parked decisions | open `status: needs-decision` issues | Surfaces each one's RECOMMENDED line — the uppercase marker wins over an incidental lowercase mention; a case-insensitive fallback catches lowercase markers |
| Lane telemetry | the loop-lane telemetry issue's per-lane comments | Each lane's `last-cycle` age (marked `STALE` past `--stale-hours`, default 6) and any `flags:` |

The telemetry issue is auto-discovered by title; pass `--telemetry-issue N` to pin it.
When no such issue exists (e.g. a consuming repo without loop-lane telemetry), that
section reports "no telemetry issue found" and the rest of the brief still renders.

## Cross-references

- `/source-control:babysit-prs` — the **authoritative** PR merge gate and readiness
  classification. The merge-ready list here is a fast gh-native glance, not a
  substitute for that skill's per-PR gate.
- `/observability` — reads locally captured telemetry (OTEL store, hook-event JSONL,
  ccusage). This skill instead reads GitHub-side queue and PR state.

## What this skill does NOT do

- **Does not mutate anything** — no label, comment, merge, or close writes.
- **Does not classify PR merge-readiness authoritatively** — use `/source-control:babysit-prs`.
- **Does not read local telemetry stores** — use `/observability`.
