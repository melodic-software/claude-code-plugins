# Fix-pass mode — apply persisted findings

The skill's `fix` action: consume the newest persisted findings file for the CURRENT branch, split findings by class, and apply — cleanup-class via the bundled `/simplify` skill, correctness-class via sequential scope-fenced fixes. The review modes are findings-only; this action is the only one that mutates the working tree.

## Step 1: Locate the findings file (current branch ONLY)

Resolve the findings location for the current branch (SKILL.md "Shared inputs") and take the newest `*.md` by filename sort — the colon-free UTC timestamps sort lexically = chronologically.

- **No findings → report cleanly, STOP.** Print: ``No findings for branch `<branch>`. Run the review first, then re-run fix.`` **NEVER scan another branch's findings** — applying one branch's findings to a different branch's working tree is the failure this fence prevents.

## Step 2: Parse + classify by finding class

Read the file. Parse the `## Findings` table (per `default-mode.md` "Findings-file shape") and the `## Unparsed` appendix. Classify each finding into ONE class:

| Class | What it is | Route |
|---|---|---|
| **cleanup** | Quality improvement that does NOT change behavior: reuse/dedup, simplification, naming, readability, dead-code removal, semantics-preserving efficiency | bundled `/simplify` |
| **correctness** | Behavioral defect: bug, security vulnerability, logic error, race condition, data-loss risk, missing error handling at a boundary, broken contract | sequential scope-fenced fix OR surface to the user |

Classification rules:

- **Classify by finding CONTENT first.** Tier is a signal, not the determinant — a SUGGESTION can be a minor correctness fix; content wins when they disagree.
- **Ambiguous → correctness (fail-safe).** `/simplify` is cleanup-only; a correctness finding routed there would be silently NOT fixed — dropping exactly the finding that matters most.
- **`## Unparsed` entries → surface to the user** for manual handling; they cannot be auto-classified.

## Step 3: Plan + confirmation gate

The fix action MUTATES the working tree. Before applying, emit the classification plan and confirm (interactive sessions; non-interactive sessions proceed without the gate):

```text
Fix-pass plan — findings: <repo-relative-path> (<N> findings)
- Cleanup-class (<n>) → /simplify
- Correctness-class (<m>) → sequential scope-fenced fix
- Surface-only (<k>, need human judgment / unparsed)
```

Honor scope narrowing ("only the correctness ones").

## Step 4: Apply

Order: correctness first (highest value, scope-fenced), then cleanup (bulk sweep). Both NON-PARALLEL.

### Correctness-class → sequential scope-fenced fix

Apply one finding at a time — concurrent fixes risk silent overwrite (last write wins).

- Each fix is scope-fenced to its finding's `Location` — touch only that file for that finding.
- **NEVER route correctness findings to `/simplify`.**
- **Surface instead of auto-applying** when a fix is low-confidence, needs architectural judgment, or has high blast radius. Auto-apply only clear, contained, high-confidence fixes.
- After each fix, re-read the touched region to confirm the edit landed as intended.

### Cleanup-class → bundled `/simplify`

Invoke the bundled `/simplify` skill (when available in the session; otherwise apply the cleanup findings directly, one file at a time).

- `/simplify` rediscovers cleanups from the working-tree diff — it does NOT read the findings file. Sound when the findings are fresh vs the working tree; note it when the findings timestamp lags far behind the latest commits.
- Zero cleanup-class findings → skip entirely; do not invoke it to "tidy anyway".

## Step 5: Report

- Cleanup-class: `<n>` findings → what changed.
- Correctness-class: `<m>` → `<applied>` fixed (list with file:line), `<surfaced>` surfaced for decision.
- Unparsed / surface-only: `<k>` listed for manual handling.

Suggest the follow-up: re-run the review to confirm the fixes resolved the findings, then the project's build/test verification before committing. The fix action does NOT run builds or tests.

## What this action does NOT do

- **Does not generate findings** — the review modes do that.
- **Does not scan other branches' findings** — current branch only.
- **Does not run builds or tests.**
