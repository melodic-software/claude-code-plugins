---
name: triage
description: "Evaluate raw intake — items the team did not author (bug reports, incoming feature requests, unsolicited PRs) — through a small state machine: raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and close. A PR is an item with attached code and enters the same intake as an issue. Use when: 'triage', 'what needs triage', 'triage this issue', 'triage this PR', 'evaluate this bug report', 'is this bug real', 'should we merge this unsolicited PR', 'attention view', 'what intake needs attention'. No number = attention view (untriaged intake). Sibling skills: /work-items:track (backlog CRUD), /work-items:work (auto-select + execute), /work-items:decompose (plan → tickets), /work-items:scan (TODO sweep)."
argument-hint: "[<number>] — issue OR pull request number to triage; empty = attention view"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Label edits, comments, and
closes route through the bound adapter's write mechanics; item creation goes through the seam
`create-item` verb; the core inlines no provider commands.

## Purpose

Evaluate **raw intake** — items the team did not author (bug reports, incoming feature requests, unsolicited PRs) — through a small state machine: raw → verified → briefed → autonomous-eligible, with side exits to needs-info, human-gated, and close.

## Usage

```text
/work-items:triage <number>     # issue OR pull request
/work-items:triage              # shows attention view (untriaged intake)
```

## Scope: raw intake only

Two rules bound what enters this flow:

- **A PR is an item with attached code.** An unsolicited or external PR enters the same intake as an issue: same states, same machine. Its diff is an **attachment to evaluate** — check it out, run the relevant tests — never an obligation to merge. Read the state names against the code: briefed means a brief exists for what to do with the diff; human-gated means a human should decide the merge.
- **Never re-triage `decompose` output.** Items published by `/work-items:decompose` (and team-authored `/work-items:track add` items) are born triaged — classified, role-labeled, and briefed at creation. They never re-enter this flow, and the attention view excludes them by construction (they carry labels from birth). If someone names one explicitly, say it is already triaged and stop.

## Triage states

State names follow the plugin's vocabulary and the canonical roles ([`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles"):

| State | Tracker marker | Meaning |
|-------|----------------|---------|
| **raw** | unlabeled or `status:needs-triage` | Untouched intake; every claim in it is unverified |
| **verified** | recorded in triage notes | The claim held up: bug reproduced, or PR diff confirmed to do what it says |
| **briefed** | brief posted + `status:ready` | Fully specified as a behavioral contract (per [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md)) |
| **autonomous-eligible** | role label (default `agent-ready`) | Briefed AND delegable — eligible for autonomous pickup from the frontier |

Side exits from any state: `status:needs-info` (returns to raw when the reporter replies), the human-gated role label (default `needs-human`) when the work is briefed but needs human judgment, or close (wontfix / duplicate / already implemented).

```text
raw → verified → briefed → autonomous-eligible (role label, default agent-ready)
 |        |          └→ human-gated (role label, default needs-human) — briefed for a human
 |        └→ status:needs-info → raw (on reporter reply)
 └→ close: wontfix | duplicate | already implemented
```

Claiming stays coordination state, not a label — assignee + lease via the seam (`/work-items:track start`, `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol"); `blocked` is a native `blocked-by` edge, not a `status:` label.

## Attention view (no number)

Show three buckets (oldest first, one-line summaries):

1. **Unlabeled** — never triaged
2. **`status:needs-triage`** — explicitly tagged for evaluation
3. **`status:needs-info` with reporter activity** — reporter replied since last triage note; ready for re-evaluation

List open items and filter into buckets programmatically (adapter: "List items", bare read). When the repo treats external PRs as a request surface, include them and tag each line `[PR]` or `[issue]` — but surface only *external* PRs (a collaborator's in-flight PR is not triage work; this filter is discovery-only, and an explicitly named PR is always triaged regardless of author). Present as a compact table.

## Triage workflow (with number)

### 1. Gather context

Read the item body, comments, and any linked PRs; for a PR, the diff too (adapter: "View item", bare read). Parse prior triage notes so resolved questions are not re-asked. Then run two checks:

- **Redundancy** — search the codebase for an existing implementation of the requested behavior by domain concept (not the request's wording), and report where you looked. Found → it's an already-implemented close (step 5).
- **Rejected-concept ledger** — when the consuming repo keeps one (`docs/out-of-scope/`, one file per concept), match the request against the concept files by **concept similarity, not keyword**. On a match, answer from the ledger instead of re-litigating: "Rejected before — `docs/out-of-scope/<concept>.md`: <reason>. Still stand?" Confirmed → append this request to the file's "Prior requests" log (re-read the file from disk first; append a line, never rewrite) and close (step 5). Reconsidered → the ledger file gets updated or removed and triage proceeds. No `docs/out-of-scope/` directory → skip the check entirely.

### 2. Recommend category + state

Classify **bug vs enhancement** first — it steers the rest of the flow (bugs get reproduced; rejected enhancements get ledgered). Then recommend:

- **Type** — bug → `Bug`; enhancement → `Feature` (or `Task` for tracked non-feature work). Native GitHub Issue Type on org repos, set through the seam; `type:` label on personal / non-org repos
- **Priority label** (`priority:p0-critical` through `priority:p3-low`)
- **Target state** — from the state machine above: needs-info, briefed for human-gated, or on track to autonomous-eligible

Wait for the user's direction before mutating anything.

### 3. Verify — BEFORE any interview

Never interview anyone about the fix for a claim nobody has confirmed. Verification precedes questioning:

- **Bug** — reproduce it from the reporter's steps; confirm the failure mode matches the report
- **PR** — confirm the diff does what it claims: check it out, run the relevant tests or commands

Report the result: confirmed (with the observed behavior / code path — the item is now **verified**, which makes a far stronger brief), failed, or insufficient detail → `status:needs-info` with a structured comment (see "Needs-info template" below).

### 4. Interview (if needed)

Only after verification (or for enhancements, where the open question is scope, not fact): when the description is vague or missing acceptance criteria, ask focused questions one at a time — resolve the most load-bearing ambiguity first. Post questions as item comments. Mark `status:needs-info` until the reporter responds.

### 5. Apply outcome

| Outcome | Action |
|---------|--------|
| Briefed, delegable | Write the brief per [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md) — durability over precision: behavioral contracts and named interfaces, **no file paths or line numbers** — apply labels + the autonomous-eligible role label (default `agent-ready`) |
| Briefed, needs human judgment | Same brief structure, plus why it can't be delegated (design decision, external access, manual QA); apply labels + the human-gated role label (default `needs-human`) |
| Needs more info | `status:needs-info` + needs-info template comment |
| Already implemented | Close pointing to where the behavior lives; do NOT ledger it (`docs/out-of-scope/` records rejections, not built features) |
| Won't fix (bug) | Close with rationale comment |
| Won't fix (enhancement) | Close with rationale comment; when the repo keeps `docs/out-of-scope/`, record the rejection in the matching concept file (re-read + append to "Prior requests", or create the concept file for a first rejection) and link it from the closing comment — applies to enhancement PRs exactly as to issues, so the same request doesn't return as fresh code |
| Duplicate | Close with link to original |

For a PR, the outcome addresses the attached code explicitly: adopt the diff (briefed for an agent or human to carry forward), rework it (brief describes the gap between the diff and the verified requirement), or decline it (close with rationale — and the ledger entry when it's a rejected enhancement).

Label edits, comments, and closes route through the adapter's write mechanics (adapter: "Edit labels / assignees", "Comment on item / edit a comment", "Close item"); the gather + attention-view reads are bare. Item creation, when triage spawns follow-up work, goes through the seam `create-item` verb (`/work-items:track add` is the canonical path).

## Needs-info template

When marking `status:needs-info`, post structured comment:

```markdown
**What we've established so far:**
- <preserved triage progress — verification results, decisions, what's known>

**What we still need from you (@<reporter>):**
1. <specific actionable question>
2. <specific actionable question>
```

Preserves partial-triage work so reporter re-engagement does not restart from zero. Questions must be specific and actionable, never "please provide more info".

## AI disclaimer

When creating comments or items during autonomous/agent triage sessions, prefix with:

> *This was generated by AI during triage.*
