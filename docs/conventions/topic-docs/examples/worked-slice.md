# Worked example — one topic, birth to graduation

Topic: adding token-refresh to an auth module. Derived slug:
`auth-token-refresh` (from the Brief topic; branch
`feat/auth-token-refresh` would derive the same).

## In flight (task branch `feat/auth-token-refresh`)

```text
docs/topics/auth-token-refresh/     <- contract slice, committed on branch
  PLAN.md                           interview writes Brief; architect appends Plan
  PRD.md                            prd (status: locked)
  design/
    design-threads.md               all RESOLVED -> architect's gate passes
    design-resolution.md
  verification/
    20260714T161500Z-outcomes.md    distilled manifest, verified_at_sha-keyed
.work/                              <- memory tier, never committed
  .gitignore                        contains "*" (self-ignoring)
  auth-token-refresh/
    EXPLORE.md                      discovery
    RESEARCH.md                     discovery (recency-gated, prunable)
    interview-checklist.md
    baselines/p95-latency.md        machine-bound measurements
    scratch/                        raw verification captures
  handoffs/
    20260714T170000Z-handoff-auth-token-refresh.md
.claude/
  topic-docs.yaml                   { contract_tier: branch }  (defaults)
```

Each implementation phase commits its `PLAN.md` progress marks together
with that phase's source changes — one commit, one story.

## PR time

The PR description carries the approved plan and the verification
summary in `<details>` blocks, by paste — the contract slice itself is
about to disappear from the diff.

## Graduation (before merge)

1. The decision to standardize on rotating refresh tokens passes the ADR
   admission test → `git mv docs/topics/auth-token-refresh/design/design-resolution.md
   docs/adr/0042-rotating-refresh-tokens.md` (vault seam, default
   backend).
2. Two follow-ups (rate-limit tuning, mobile client migration) become
   tracker items through the work-items seam; the fog-of-war question
   ("do we need per-device revocation?" — precisely statable, not yet
   answerable) files as a decision item.
3. The prune commit deletes `docs/topics/auth-token-refresh/`, and its
   message plus the PR body point at: the PR description (plan +
   verification), `docs/adr/0042`, and the tracker items.
4. The required check confirms the net PR diff contains no
   `docs/topics/**` path. Merge.

## After

`main` carries: the code, the ADR, the (pruned) history in the PR
record. `.work/auth-token-refresh/` lingers locally until scratch
cleanup; nothing on main ever drifts, because nothing generated stayed.
