# Run outputs and templates

## Contents

- [Run directory](#run-directory)
- [Claim inventory](#claim-inventory)
- [Decision brief](#decision-brief)
- [User-run scripts](#user-run-scripts)
- [PR drafts](#pr-drafts)

## Run directory

Each run writes under `<plugin data>/audit-friction/runs/<UTC stamp>/`:

| File | Written by | Holds |
|---|---|---|
| `friction.json` | `<skill-dir>/scripts/friction.py mine` | Window, per-key counts by side with class hints, shapes, perf signals, events |
| `classes.md` | classify agent | Class A-E per key with evidence sessions; the person's operating principles, quoted |
| `merge.txt` | `/harness-config:audit-permission-state` | The effective permission set, one `effective <kind> ...` line per rule |
| `cause.json` | `friction.py cause` | Each denial and approved prompt grouped with candidate rules and a hint |
| `PLAN.md` | plan agent | Ranked fixes with exact edits, safety and `Basis:` |
| `inventory.json` | plan agent | Every claim the plan rests on |
| `DECISION-BRIEF.md` | main session | What the person approves |
| `DECISIONS.md` | main session | Every approval, verbatim and dated |
| `scripts/` | main session | User-run scripts, one per repository |
| `PR-DRAFTS.md` | main session | Fixes that go through a normal pull request |

`mine --save-baseline` also copies `friction.json` to `<plugin data>/audit-friction/baselines/`;
`friction.py diff --data-dir` reads the newest one.

## Claim inventory

```json
{"claims": [
  {"id": "c1", "type": "fact", "text": "...", "consequential": true, "basis": "file:line or URL"}
]}
```

`type` is one of `fact`, `specific`, `premise`, `recommendation`. `friction.py estimate` counts
claims, the consequential ones, and the recommendations it sends to a challenge pass.

## Decision brief

```markdown
# Decision brief: <window>

Approve everything below with one reply ("approve as recommended"), or name the items to change.

## Part 1: confirmed edits (exact text)
<per edit: file, before, after, class, events it removes, Basis>

## Part 2: ranked items
| # | Fix | Class | Events per active hour | Sessions | Route | Recommendation |

## Open questions
<per question: what it is, the options, the recommendation, what it unblocks>

## Consequential edits
<each self-modification, security-posture or production edit, named once, with its script>
```

## User-run scripts

One script per repository holds every approved edit the classifier would block. Show the script
before asking the person to run it, then read its log back.

- Idempotent: rerunning after a partial run finishes the job.
- Self-contained: it creates its own worktree or branch from the default branch, installs the
  repository's dependencies there (a fresh worktree has none), applies the edits, runs the
  repository's own checks, commits, pushes and opens a draft PR.
- It never force-pushes or merges; merging follows the person's standing authorization.
- It writes a log beside itself and exits non-zero on the first failure, naming the step.

## PR drafts

```markdown
| # | Repository | Title (Conventional Commits) | Fix | Class | Verification |
```

One row per pull request, grouped so that every change a later rollout depends on lands first.
