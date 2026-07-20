# Fix-pass mode — apply persisted findings

The skill's `fix` action: consume the newest persisted findings file for the CURRENT branch, split findings by class, and apply — cleanup-class via the optional in-session `/simplify` skill, correctness-class via sequential scope-fenced fixes. The review modes are findings-only; this action is the only one that mutates the working tree.

## Step 1: Locate the findings file (current branch ONLY)

Resolve the findings location for the current branch (SKILL.md "Shared inputs"; the resolved `<memory_dir>/reviews/<branch-slug>/` home, default `.work/reviews/`) and take the newest `*.md` **whose frontmatter declares `type: review-findings` AND whose `branch:` value equals the current branch name exactly** (the fanout contract in `default-mode.md` "Findings-file shape") by filename sort — the colon-free UTC timestamps sort lexically = chronologically. The directory is shared with `quality-gate` modes, whose reports have a different shape; skip any file without that frontmatter marker rather than parsing it as the fanout contract. The `branch:` check is load-bearing: the slug is lossy (`feature/foo` and `feature-foo` map to the same directory), so the directory alone does not prove the findings belong to this branch.

- **No findings → report cleanly, STOP.** Print: ``No findings for branch `<branch>`. Run the review first, then re-run fix.`` **NEVER scan another branch's findings** — applying one branch's findings to a different branch's working tree is the failure this fence prevents.

## Step 2: Parse + classify by finding class

Read the file. Parse the `## Findings` table (per `default-mode.md` "Findings-file shape") and the `## Unparsed` appendix. Classify each finding into ONE class:

| Class | What it is | Route |
|---|---|---|
| **cleanup** | Quality improvement that does NOT change behavior: reuse/dedup, simplification, naming, readability, dead-code removal, semantics-preserving efficiency | optional in-session `/simplify` |
| **correctness** | Behavioral defect: bug, security vulnerability, logic error, race condition, data-loss risk, missing error handling at a boundary, broken contract | sequential scope-fenced fix OR surface to the user |

Classification rules:

- **Classify by finding CONTENT first.** Tier is a signal, not the determinant — a SUGGESTION can be a minor correctness fix; content wins when they disagree.
- **Ambiguous → correctness (fail-safe).** `/simplify` is cleanup-only; a correctness finding routed there would be silently NOT fixed — dropping exactly the finding that matters most.
- **`## Unparsed` entries → surface to the user** for manual handling; they cannot be auto-classified.

## Step 3: Plan + confirmation gate

The fix action MUTATES the working tree — the only fanout action that does. ALWAYS emit the classification plan first:

```text
Fix-pass plan — findings: <repo-relative-path> (<N> findings)
- Cleanup-class (<n>) → /simplify
- Correctness-class (<m>) → sequential scope-fenced fix
- Surface-only (<k>, need human judgment / unparsed)
```

Then gate on the session context and the `--yes` / `-y` flag (SKILL.md "Arguments"). Every side-effect path is explicitly gated — the gate never self-downgrades unattended:

| Session | `--yes` | Gate |
|---|---|---|
| Interactive | absent | Confirm with the user before applying. Honor scope narrowing ("only the correctness ones"). |
| Interactive | present | Skip the confirmation prompt and apply. |
| Non-interactive (`CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop) | absent | **STOP after the plan — mutate nothing.** The plan IS the report: an operator reviews what would have been applied, then re-runs with `--yes`. Fail-safe default — forgetting the flag pauses a lane for one cycle; the reverse mistake mutates a tree unconfirmed. |
| Non-interactive | present | Apply, then write the applied-plan record (Step 5). |

The `fix` argument opts INTO fix mode; `--yes` is the separate, explicit consent to mutate a tree with no human watching. A non-interactive session with no `--yes` is never consent.

## Step 4: Apply

Order: correctness first (highest value, scope-fenced), then cleanup (bulk sweep). Both NON-PARALLEL.

### Correctness-class → sequential scope-fenced fix

Apply one finding at a time — concurrent fixes risk silent overwrite (last write wins).

- Each fix is scope-fenced to its finding's `Location` — touch only that file for that finding.
- **NEVER route correctness findings to `/simplify`.**
- **Surface instead of auto-applying** when a fix is low-confidence, needs architectural judgment, or has high blast radius. Auto-apply only clear, contained, high-confidence fixes.
- After each fix, re-read the touched region to confirm the edit landed as intended.

### Cleanup-class → optional in-session `/simplify`

Invoke the `/simplify` skill when available in the session; otherwise apply the cleanup findings directly, one file at a time.

- `/simplify` rediscovers cleanups from the working-tree diff — it does NOT read the findings file. Sound when the findings are fresh vs the working tree; note it when the findings timestamp lags far behind the latest commits.
- Zero cleanup-class findings → skip entirely; do not invoke it to "tidy anyway".

## Step 5: Report

- Cleanup-class: `<n>` findings → what changed.
- Correctness-class: `<m>` → `<applied>` fixed (list with file:line), `<surfaced>` surfaced for decision.
- Unparsed / surface-only: `<k>` listed for manual handling.

### Applied-plan record (headless apply only)

When the apply ran under `--yes` in a non-interactive session, ALSO persist the applied plan as a durable record — a headless apply had no human watching it mutate the tree, so the record is the after-the-fact review surface. Interactive and headless-stop paths write no record (a human saw the interactive apply; the stop path mutated nothing). Run the self-ignore guard, then write into the same branch findings location (SKILL.md "Shared inputs") as `<UTC-timestamp>-fix-pass-applied.md` (`date -u +%Y%m%dT%H%M%SZ`, colon-free):

```markdown
---
type: fix-pass-record
date: <ISO-8601 UTC>
branch: <branch>
source-findings: <repo-relative path of the consumed findings file>
---

## Applied fix-pass plan

- Cleanup-class (<n>) → /simplify: <what changed>
- Correctness-class (<m>): <applied file:line list>; <surfaced> surfaced for decision
- Surface-only / unparsed (<k>): <listed>
```

The `type: fix-pass-record` marker is deliberately NOT `review-findings`, so Step 1's locator skips this record and never re-consumes it as findings (the same frontmatter fence that already skips `quality-gate` reports). The record lands in the gitignored memory-tier findings dir, so it is checkout-local durable for the operator who ran the lane, not a committed artifact — matching this issue's "local, reversible" scope.

Follow-up: after correctness-class fixes, re-run the review — the fixer confirming its own fix resolved a finding is the producer verifying its own work, and a fresh review pass re-fans-out to reviewers that did NOT apply the fix. Treat that re-review as **required** for correctness-class findings, not merely suggested; cleanup-class fixes are mechanical and behavior-preserving, so their `/simplify` verification stands on its own. Either way, run the project's build/test verification before committing — the fix action does NOT run builds or tests.

## What this action does NOT do

- **Does not generate findings** — the review modes do that.
- **Does not scan other branches' findings** — current branch only.
- **Does not run builds or tests.**
