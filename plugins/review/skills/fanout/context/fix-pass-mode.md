# Fix-pass mode — apply persisted findings

The skill's `fix` action: consume the UNCONSUMED persisted findings for the CURRENT branch — the merged set across every producer, not one file — split findings by class, and apply — cleanup-class via the optional in-session `/simplify` skill, correctness-class via sequential scope-fenced fixes. The review modes are findings-only; this action is the only one that mutates the working tree.

## Step 1: Build the merge set (current branch ONLY)

Nothing authenticates the writer of a findings file: any component of any shape that persists a conforming file reaches this action, so `review:fanout` is one producer among several. Taking only the newest file would let a later producer silently shadow an earlier one's findings — a green run with hidden findings, the failure class `docs/conventions/liveness-assertion/README.md` "Fail loud" exists to prevent. **The consumed input is therefore a set, and this action merges it rather than picking a winner.**

Resolve the findings location for the current branch (SKILL.md "Shared inputs"; the resolved `<memory_dir>/reviews/<branch-slug>/` home, default `.work/reviews/`), then build the set in two passes:

1. **Candidates** — EVERY `*.md` in that directory **whose frontmatter declares `type: review-findings` AND whose `branch:` value equals the current branch name exactly** (the fanout contract in `default-mode.md` "Findings-file shape"). The directory is shared with `quality-gate` modes, whose reports have a different shape; skip any file without that frontmatter marker rather than parsing it as the fanout contract. The `branch:` check is load-bearing: the slug is lossy (`feature/foo` and `feature-foo` map to the same directory), so the directory alone does not prove the findings belong to this branch.
2. **Subtract what was already consumed** — every `*.md` in the same directory declaring `type: fix-pass-record` **whose own `branch:` value ALSO equals the current branch name exactly** lists the files it consumed in `source-findings:` (Step 5). Drop every listed file name from the candidate set. The exact-`branch:` filter binds BOTH sides for the same reason it binds the first: a record left by a slug-collided branch would otherwise silently truncate this set, re-creating the hidden-findings failure inside the fix that closes it.

Sort the surviving set by file name — the colon-free UTC timestamps sort lexically = chronologically — so the merged report is deterministic.

- **Empty set → report cleanly, STOP.** Print: ``No unconsumed findings for branch `<branch>`. Run the review first, then re-run fix.`` **NEVER scan another branch's findings** — applying one branch's findings to a different branch's working tree is the failure this fence prevents.
- **A one-file set reduces to the previous single-producer behavior byte-for-byte** — the merge, the union, and the dedup are all identities on one input. That is the migration's safety property, not an accident.
- **Shared findings directory.** A `memory_dir` resolving outside the worktree serves several worktrees, and those worktrees are on different branches. The exact-`branch:` filter on BOTH the candidates and the records is the whole of what keeps that correct — never the directory path, and never the file's location on disk.

## Step 2: Merge, then classify by finding class

Read EVERY file in the set. From each, parse the `## Findings` table (per `default-mode.md` "Findings-file shape") and the `## Unparsed` appendix. A conforming file MAY carry a `> DEGRADED:` blockquote above `## Findings` (`run-everything-mode.md` "Degraded notice"); it is a coverage notice, not a finding — carry it into the Step 3 plan and skip it when parsing rows.

Merge across the set before classifying:

- **Findings rows** — concatenate, then collapse only rows sharing an identical `Location` AND identical `Finding` text; a collapsed row names every contributing producer in `Surface(s)`. Everything else stays a distinct row.
- **`## Unparsed`** — union by concatenation. Never drop one file's appendix because another had none.
- **`## Surfaces`** — union, each producer's ran/returned-nothing line attributed to it. A surface that ran and returned nothing is coverage information; reporting one producer's line would hide it.
- **`tier:`** — report EVERY consumed file's tier. One tier does not win; tiers describe different producers' change scopes and are not comparable.

**Dedup is presence-only, and that is narrower than Stage 3's key on purpose.** `findings-normalization.md` places dedup at "Stage 3 Sonnet (semantic merge)" — an LLM stage this action does not run — and orders "**Minimize FALSE-MERGE over FALSE-SPLIT** — a false merge silently drops a real issue". The tempting key, normalized path plus a ±3-line bucket, would merge distinct defects at `foo.ts:42` and `foo.ts:44`; since Step 4 applies one `Action` per row and fences each fix to that row's file, one producer's remediation would be discarded with no trace. A false split adds a duplicate row an operator can see. Duplicate rows are therefore possible and accepted.

Classify each surviving finding into ONE class:

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
Fix-pass plan — consumed <S> findings file(s), <N> findings after merge
- <file-name> (tier: <tier>)[, DEGRADED: <notice>]
- ... one line per consumed file
- Cleanup-class (<n>) → /simplify
- Correctness-class (<m>) → sequential scope-fenced fix
- Surface-only (<k>, need human judgment / unparsed)
```

The header names the consumed **set**, one line per file — an operator who cannot see which producers contributed cannot tell a two-producer merge from a one-producer shadow, which is the condition this whole step exists to make visible.

Then gate on the session context and the `--yes` / `-y` flag (SKILL.md "Arguments"). Every side-effect path is explicitly gated — the gate never self-downgrades unattended:

| Session | `--yes` | Gate |
|---|---|---|
| Interactive | absent | Confirm with the user; on consent apply, then write the consumption record (Step 5). Honor scope narrowing ("only the correctness ones"). A declined gate applies nothing and writes no record. |
| Interactive | present | Skip the confirmation prompt, apply, then write the consumption record (Step 5). |
| Non-interactive (`CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop) | absent | **STOP after the plan — mutate nothing, write no record.** The plan IS the report: an operator reviews what would have been applied, then re-runs with `--yes`. Fail-safe default — forgetting the flag pauses a lane for one cycle; the reverse mistake mutates a tree unconfirmed. |
| Non-interactive | present | Apply, then write the consumption record (Step 5). |

**Every path that applies writes the record; the one path that applies nothing writes none.** The record is what marks its inputs consumed, so an apply that skipped it would leave those findings in the next merge set and re-inject remediations the required post-fix re-review has already resolved.

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

- `/simplify` rediscovers cleanups from the working-tree diff — it does NOT read the findings files. Sound when the findings are fresh vs the working tree; note it when the OLDEST consumed file's timestamp lags far behind the latest commits.
- Zero cleanup-class findings → skip entirely; do not invoke it to "tidy anyway".

## Step 5: Report + consumption record

- Cleanup-class: `<n>` findings → what changed.
- Correctness-class: `<m>` → `<applied>` fixed (list with file:line), `<surfaced>` surfaced for decision.
- Unparsed / surface-only: `<k>` listed for manual handling.

### Consumption record (EVERY apply path)

Whenever the action applied anything, ALSO persist the applied plan as a durable record. It serves two purposes: an after-the-fact review surface for an apply nobody watched, and — the load-bearing one — the ledger Step 1 subtracts by. Run the self-ignore guard (a fix-first session may be the first memory-tier write, so the guard is not headless-only), then write into the same branch findings location (SKILL.md "Shared inputs") as `<UTC-timestamp>-fix-pass-applied.md` (`date -u +%Y%m%dT%H%M%SZ`, colon-free):

```markdown
---
type: fix-pass-record
date: <ISO-8601 UTC>
branch: <branch>
source-findings:
  - 20260815T044501Z-review.md
  - 20260815T051230Z-mutation-survivors.md
---

## Applied fix-pass plan

- Consumed (<S> files): <file-name list, matching source-findings>
- Cleanup-class (<n>) → /simplify: <what changed>
- Correctness-class (<m>): <applied file:line list>; <surfaced> surfaced for decision
- Surface-only / unparsed (<k>): <listed>
```

**`source-findings:` is ALWAYS a YAML block sequence of bare file NAMES — one entry even for a single file, never a bare scalar.** Step 1 matches those entries against candidate file names, and a writer emitting a scalar where the reader expects a sequence under-matches silently, re-consuming findings this record was written to retire. Names, not paths, are the key on purpose: the resolved `memory_dir` can differ between the session that wrote the findings and the session that applies them (a second checkout of the same branch, or a `memory_dir` outside the worktree), while the branch findings directory is a single home whose `<UTC-timestamp>-<topic>.md` names are already unique within it. Comparing paths would fail exactly where comparing names holds.

The `type: fix-pass-record` marker is deliberately NOT `review-findings`, so Step 1's candidate pass skips this record and never re-consumes it as findings (the same frontmatter fence that already skips `quality-gate` reports). The record lands in the gitignored memory-tier findings dir, so it is checkout-local durable for the operator who ran the lane, not a committed artifact — local and reversible.

**Consumption is per FILE, not per row.** A file whose rows were partly surfaced rather than applied (Step 4), or narrowed by the operator ("only the correctness ones"), is still marked consumed in full. Those rows are named in the record body and are recovered by re-running the review — a fresh pass re-finds anything still present in the tree and persists it as a NEW file, which enters the next merge set as a fresh candidate. Do NOT expect deferred rows to survive in the merge set; re-run the review instead.

Follow-up: after correctness-class fixes, re-run the review — the fixer confirming its own fix resolved a finding is the producer verifying its own work, and a fresh review pass re-fans-out to reviewers that did NOT apply the fix. Treat that re-review as **required** for correctness-class findings, not merely suggested; cleanup-class fixes are mechanical and behavior-preserving, so their `/simplify` verification stands on its own. Either way, run the project's build/test verification before committing — the fix action does NOT run builds or tests.

## What this action does NOT do

- **Does not generate findings** — the review modes do that.
- **Does not scan other branches' findings** — current branch only.
- **Does not dedup semantically** — presence-only, per Step 2. Near-miss duplicates survive as separate rows by design.
- **Does not run builds or tests.**
