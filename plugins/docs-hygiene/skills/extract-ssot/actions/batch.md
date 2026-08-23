# `batch` action — multi-candidate orchestration

## Contents

- [When to invoke](#when-to-invoke)
- [Inputs](#inputs)
- [Steps](#steps)
- [Step 1 — Pre-flight](#step-1--pre-flight)
- [Step 2 — Verify filter (HARD GATE for batches ≥5)](#step-2--verify-filter-hard-gate-for-batches-5)
- [Step 3 — Filter](#step-3--filter)
- [Step 4 — File-overlap matrix](#step-4--file-overlap-matrix)
- [Step 5 — Wave grouping (graph coloring)](#step-5--wave-grouping-graph-coloring)
- [Step 6 — Dispatch policy](#step-6--dispatch-policy)
- [Step 7 — Lesson injection](#step-7--lesson-injection)
- [Step 8 — Per-dispatch capture](#step-8--per-dispatch-capture)
- [Step 9 — Lesson append](#step-9--lesson-append)
- [Step 10 — Batch audit log](#step-10--batch-audit-log)
- [Side observations](#side-observations)
- [Recheck triggers](#recheck-triggers)
- [Cross-references](#cross-references)

Multi-candidate orchestration. Computes a file-overlap matrix across candidates, dispatches refuse-fast `verify` to filter, then runs `plan`/`execute` in non-overlapping parallel waves OR strict sequential order (concurrent-write risk → sequential by default). Accumulates lessons in `context/lessons.md` between subagent dispatches.

Loaded by `/docs-hygiene:extract-ssot batch <cluster-list>`. Private surface — invoke via `/docs-hygiene:extract-ssot batch`, never cite this file directly (contract: `/docs-hygiene:audit-encapsulation`).

## When to invoke

| Use case | Invoke |
|----------|--------|
| `/docs-hygiene:extract-ssot identify` produced 5+ candidates and you want efficient orchestration | YES |
| Manual list of candidates to migrate in one pass | YES |
| Single candidate | NO — use `/docs-hygiene:extract-ssot plan <name>` directly |
| < 3 candidates | NO — manual sequential dispatch is simpler |

This is NOT the bundled Claude Code `/batch` skill. Bundled `/batch` is polyglot worktree-parallelized refactor per [code.claude.com/docs/en/commands](https://code.claude.com/docs/en/commands); this `batch` action is local SSOT-cluster orchestration.

## Inputs

```text
/docs-hygiene:extract-ssot batch <candidate-1> [<candidate-2> ... <candidate-N>]
  [--min-instances=<N>] [--buckets=<list>] [--fix] [--dry-run] [--yes]
```

OR resume from working notes if a `batch` phase is mid-flight.

Candidate names match `/docs-hygiene:extract-ssot identify` output's cluster names.

`--min-instances`, `--buckets`, `--fix`, `--dry-run`, and `--yes` pass through to the batch surface
with the semantics defined in `actions/identify.md` "Flags": `--min-instances` / `--buckets` filter
which buckets enter the dispatch list, and `--fix` / `--dry-run` / `--yes` govern the
non-abstracting remedy sweep. `--fix` never creates an artifact in any wave.

## Steps

```text
1. Pre-flight: read context/lessons.md (snapshot for this batch)
2. For each candidate: invoke `verify <candidate>` (Tier 0 grep, citation state, etc.)
3. Filter: drop REFUSE-* candidates; keep PROCEED + WARN
4. Compute file-overlap matrix across surviving candidates
5. Group into non-overlapping waves (graph coloring on overlap matrix)
6. Dispatch wave-by-wave; SEQUENTIAL within wave when shared files exist
7. Inject lesson snapshot into each subagent's prompt
8. Per dispatch: capture verdict + new lessons surfaced
9. Append new lessons to context/lessons.md (Lesson N+1 entries)
10. Write a batch audit log entry to the working notes
```

## Step 1 — Pre-flight

Read `context/lessons.md` once at batch start. The snapshot is the lesson set injected into all subagent dispatches in this batch. Avoids race conditions where subagent A and B both append simultaneously.

## Step 2 — Verify filter (HARD GATE for batches ≥5)

For each candidate, invoke `verify` (private action — see `actions/verify.md`). Capture per-candidate output.

**HARD GATE rule (per Lesson 10):** when `<cluster-list>` size ≥ 5, `verify` is MANDATORY before any `plan`/`execute` dispatch — refuse-fast at this step rather than spawning subagents on false-positive candidates. Subagent identify passes routinely produce ~95% FP rates without per-cluster Tier 0 verification; gating here prevents wasted dispatches. Smaller batches (1-4 candidates) may skip `verify` per user discretion (the action is still OPTIONAL there).

If the batch fails the verify-gate (≥80% candidates REFUSE), abort the batch and surface the diagnostic to the user — it likely signals the identify pass needs hardening per the Discrimination rules in `actions/identify.md`. Don't dispatch `plan`/`execute` on the surviving 20%; the user picks scope manually.

Each verdict carries the bucket `verify` Gate 1 assigned. A sub-three bucket is not a refusal — an
N=1 or N=2 candidate PROCEEDs with its non-abstracting remedies and stays in the dispatch list.

```yaml
candidate: <name>
verify-status: PROCEED | REFUSE-{reason} | WARN
bucket: N=1 | N=2 | N>=3
permitted-remedies: [...]
verify-evidence: [...]
```

Output forms the batch summary's first two columns.

## Step 3 — Filter

Drop candidates with `REFUSE-*` status from the dispatch list. Keep `PROCEED` + `WARN` at every
bucket — N=1 and N=2 candidates survive the filter and dispatch with the non-abstracting remedies
their bucket permits, never an artifact-creating one. Apply `--min-instances` / `--buckets` here as
a second, caller-chosen filter; record what they excluded so a suppressed bucket does not read as an
empty one. Surface the dropped candidates with reasons in the batch audit log so the user sees the
refuse-fast savings.

The ≥80%-refusal abort check counts only `REFUSE-*` verdicts. Bucket distribution is a reporting
fact, not a refusal — a roster that is mostly N=1 is a healthy finding, not a failed identify pass.

## Step 4 — File-overlap matrix

For each surviving candidate, identify the file set the candidate would touch:

- ALLOWED list from the candidate spec (output target file + sweep call sites)
- FORBIDDEN list (other candidates' territory; previous-batch territory)

Compute overlap:

```text
        | C1   | C2   | C3   | C4   |
   C1   |  -   |  ∅   |  X   |  ∅   |
   C2   |  ∅   |  -   |  ∅   |  X   |
   C3   |  X   |  ∅   |  -   |  ∅   |
   C4   |  ∅   |  X   |  ∅   |  -   |
```

`X` = at least one shared file (write conflict); `∅` = disjoint.

Implementation: for each pair (Ci, Cj), grep both candidate specs for ALLOWED files, intersect sets. If the intersection is non-empty, mark `X`. Capture the full intersection list in the audit log.

## Step 5 — Wave grouping (graph coloring)

Build an undirected graph: nodes = candidates, edges = `X` overlaps. Color with greedy graph-coloring; nodes of the same color = one wave.

Naive heuristic when N < 10:

- Sort candidates by overlap-degree (highest first)
- Wave 1 = highest-degree candidate; add candidates with no edge to wave-1 members
- Wave 2 = next highest-degree candidate not yet assigned; same rule
- Repeat

Output: wave-grouped candidate list:

```yaml
waves:
  - wave: 1
    candidates: [C1, C2]
  - wave: 2
    candidates: [C3, C4]
```

## Step 6 — Dispatch policy

**SEQUENTIAL within wave when ANY of:**

- Wave has > 1 candidate AND any pair has shared files (collision risk — concurrent agents editing the same file silently overwrite each other; there is no file-level locking)
- Wave touches files that another wave already touched in this batch (chronological dependency)
- Candidate has `verify-status: WARN` (an extra adversarial-review step is warranted)

**PARALLEL within wave allowed when ALL of:**

- All candidates in the wave are pairwise disjoint per the overlap matrix
- No candidate touches files already edited in earlier waves
- All candidates have `verify-status: PROCEED` (HIGH confidence)

Default: sequential. Parallel is opt-in via the batch-action argument `--parallel-waves`. Parallel collisions are a real bug class (no file locking); the default conservatism is intentional.

**Worker concurrency and rate limits.** Whatever the wave grouping allows, concurrent worker
dispatches stay under the `context/orchestrated-mode.md` ceiling (default 2, static) and honor its
between-dispatch rate-limit-guard check when the consuming machine exposes the guard's snapshot.
Wave grouping decides *what may* run together; the ceiling decides *how much* actually does.

## Step 7 — Lesson injection

Each subagent dispatched in this batch receives the lesson snapshot from Step 1 in its prompt:

```text
## Empirical lessons from prior batches

(snapshot of context/lessons.md as of batch start)

Lesson 1 — Discriminating-phrase grep beats keyword density
... (full lessons.md body)
```

The subagent treats lessons as advisory — applies them in its own decision-making but does NOT modify `lessons.md` directly. New lessons from THIS subagent's run are returned in the deliverable summary, not committed by the subagent.

## Step 8 — Per-dispatch capture

Each subagent return value contains:

```yaml
candidate: <name>
verdict: EXTRACTED | REFUSED-{reason} | DEFERRED
files-modified: [...]
new-lessons: [free-form patterns observed]
sanity-check-evidence: [...]
```

`new-lessons` is the field where empirical patterns surface for the orchestrator to codify.

## Step 9 — Lesson append

After all waves complete, the orchestrator (main session) reviews `new-lessons` from all dispatches:

- Cross-check against existing lessons.md (avoid duplicate Lesson N entries)
- For genuinely novel patterns: append `## Lesson N+1: <name>` per `context/lessons.md` "Append guidance for future batches"
- The Source field references THIS batch's audit log
- The Encoded-in field documents which downstream artifacts (anti-patterns.md, verify gates) should consume the new lesson

Subagent-reported lessons are synthesis until the orchestrator re-verifies them with its own grep — verify each novel-lesson claim before the lessons.md append.

If no novel patterns surface, no append. Don't force.

## Step 10 — Batch audit log

Append to the working notes:

```markdown
---
type: batch
date: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
batch-size: <N>
---

## Batch summary

| # | Candidate | Bucket | Verify | Verdict | Wave | Files modified |
|---|-----------|--------|--------|---------|------|----------------|
| 1 | C1 | N≥3 | PROCEED | EXTRACTED | 1 | path1, path2 |
| 2 | C2 | N≥3 | PROCEED | REFUSED-low-roi | 1 | (none) |
| 3 | C3 | N=1 | REFUSE-already-cites-canonical | (skipped) | (n/a) | (none) |
| 4 | C4 | N=2 | PROCEED | OWNER-NAMED | 2 | path3, path4 |
| ... | | | | | | |

## File-overlap matrix
<full matrix from Step 4>

## Wave plan
<wave grouping from Step 5>

## Dispatch policy
- Sequential / parallel + rationale

## Lessons accumulated
- Lesson N+1: <name> (if any)

## Refuse-fast savings
<n> candidates refused at verify; <n> subagent dispatches saved
```

The log doubles as the batch retrospective and as source material for the PR description.

## Side observations

Hard limit ≤2 side notes per response:

- If multiple candidates surface the SAME refuse-pattern (e.g. 3 candidates REFUSE-already-cites-canonical for the same canonical file), surface ONE side observation suggesting the canonical file document a stable heading for its audience; batch the rest into the log
- If all candidates in a wave PROCEED but the wave's parallel-vs-sequential choice was nontrivial, surface the rationale (so the user can adjust `--parallel-waves` next time)

## Recheck triggers

| Condition | Action |
|-----------|--------|
| Claude Code ships file-level locking for concurrent sessions | Re-evaluate parallel-by-default; relax the sequential-within-wave constraint |
| `lessons.md` exceeds 400 lines | Trigger archive-and-trim per `context/lessons.md` "Append guidance for future batches"; preserve the most-recent + greatest-impact lessons inline |
| The `verify` action ships a new gate (Gate 7+) | Update the Step 2 verify filter to capture new reason codes |
| Anthropic ships a canonical batch/multi-target action convention for skills | Re-align the Step 6 dispatch policy; expose `--parallel-waves` differently if upstream prescribes |
| `/docs-hygiene:extract-ssot batch` consistently produces > 50% refuse-fast filtering | Diagnostic signal that the `/docs-hygiene:extract-ssot identify` survey heuristic needs tuning; document the tuning in `lessons.md` |

## Cross-references

- `actions/verify.md` — Step 2 sub-routine; refuse-fast gate per candidate
- `context/lessons.md` — Step 1 snapshot source; Step 9 append destination
- `context/decision-framework.md` "Pre-extraction Tier 0 checklist" — the same gates `verify` runs, documented for human-readable batch review
- `context/anti-patterns.md` #11 / #12 / #13 — REFUSE patterns the verify filter encodes
- SKILL.md "Evidence discipline" — subagent return values are synthesis by default; the orchestrator MUST verify novel-lesson claims before the lessons.md append
- `/docs-hygiene:extract-ssot identify` — produces the ranked candidate list this batch action consumes
- Bundled Claude Code `/batch` skill — distinct concern (worktree-parallelized polyglot refactor); see SKILL.md "What this skill does NOT do"
