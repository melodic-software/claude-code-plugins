# audit-pass — the run contract

Finding identity, where the report lives, run state, resumability, the report schema, and the three
finding tiers with their properties. Every rule here is stated as a condition a test can assert.

Terms: a **run** is one invocation against one **target**; a **lane** is one check applied to one
surface class; the **scan set** is the set of files a run reads.

## 1. Finding identity

Prose judgements are undiffable. Identity is a four-part tuple, emitted machine-readably.

```text
identity = (surface, check, anchor, claim)
```

- **`surface`** — the file's *logical* path, never a machine-absolute one. Project-scope surfaces are
  repo-relative POSIX paths with no leading `./`; user-scope and managed-policy surfaces are
  scope-prefixed (`user:.claude/CLAUDE.md`, `managed:CLAUDE.md`). A report is then comparable across
  machines whose absolute paths differ.
- **`check`** — fully qualified, `<plugin>/<skill>/<check>`. A bare check id is ambiguous across
  catalogs.
- **`anchor`** — **content-derived, never line-derived**: `sha256(normalized_excerpt)` truncated to
  12 hex characters. Normalization strips trailing whitespace, collapses internal whitespace runs to
  one space, and strips surrounding markdown emphasis markers; case is preserved, because these
  surfaces contain code and identifiers. A human-readable heading path (`## Rules > ### Naming`)
  travels alongside for legibility only — the hash is what identity compares. A line number would
  shift whenever anything above it changed, churning the whole report on an unrelated edit.
- **`claim`** — the check's canonical claim id plus its bound parameters, never free prose. A finding
  names one template from the check's declared set and supplies its parameters; prose is a rendering
  of the claim, never the claim itself.

**`finding_id` = `sha256` of the four fields joined by `\x1f`, truncated to 16 hex characters.**

| # | Assertion |
|---|---|
| 1.1 | For a fixed tree, `finding_id` is stable across runs, working directories, operating systems, and path separators. |
| 1.2 | Inserting an unrelated paragraph above a finding does not change its `finding_id`. |
| 1.3 | Every emitted finding validates against the report schema, and its `claim` id exists in the cited check's declared template set. An undeclared claim id is a **hard error**, not a warning — that is what stops prose leaking back in. |

## 2. Where the report lives

**A run never writes into its own scan set.** If run 1 writes a report into the tree, run 2's tree is
not unchanged and the idempotence property is unfalsifiable by construction.

- The report goes under `${CLAUDE_PLUGIN_DATA}`, which resolves outside any target repository and
  survives plugin updates, at `runs/<state-key>/<run-id>/findings.json`.
- `--report-to <path>` redirects it into the target tree. The run then **must** add that path to the
  exclusion set for subsequent runs and say so in its output.

| # | Assertion |
|---|---|
| 2.1 | After a run against a clean git worktree with no redirect, `git status --porcelain` is empty. |
| 2.2 | With a redirect, a second run's scan set excludes the redirected path, and the two runs' derived identity sets are still equal. |

## 3. Run state, keying, and concurrency

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project, so state keyed by working directory would
collide or fragment depending on where the operator happened to stand.

**`<state-key>` = `<repo-identity>/<worktree-discriminator>`.**

- **`repo-identity`** — for a git repository, the first configured remote URL normalized to
  `host/owner/repo`, lowercased, `.git` suffix and credentials stripped. With no remote,
  `local/<sha256 of the canonicalized repo root>` truncated to 12.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository on different branches legitimately hold different content and must not
  share a run report.

Suppressions are keyed differently on purpose (§4): they are a decision about the *repository*, not
about a checkout, so they are shared across worktrees and committed where the operator owns the
target.

**Concurrency.**

- A read-only run takes **no lock**; concurrent read-only runs are safe and are not serialized.
- An applying run takes an **exclusive advisory lock** at `runs/<state-key>/lock`, containing the
  process id and an ISO-8601 start timestamp.
- A second applying run for the same state key **refuses and exits non-zero**, naming the holder's
  pid and start time. It does not wait — a pass over a large tree runs long, and a silent queue looks
  like a hang.
- A lock whose recorded pid is not alive **and** whose timestamp is older than 30 minutes is stale
  and is reclaimed, with the reclamation reported in the run output.

| # | Assertion |
|---|---|
| 3.1 | Two applying runs launched concurrently against one target: exactly one proceeds, the other exits non-zero naming the holder. |
| 3.2 | Two read-only runs launched concurrently both complete, and their derived identity sets are equal. |
| 3.3 | A run launched from a subdirectory produces the same state key as one launched from the root. Working directory is never an input. |

## 4. Suppression, per target class

**The governing rule: an inline marker is permitted only where the pass may write; everywhere else
suppression is central and keyed by `finding_id`.**

| Target class | Suppression site | Why |
|---|---|---|
| A project-scope file the pass may edit | inline marker at the finding's site | Local, reviewable in the same diff as the content it governs, and it travels with the content |
| A file the pass does not own | the central record, keyed by `finding_id` | Editing a file you do not own to silence a report is a boundary violation dressed as configuration |
| A user-scope file | the central record only; **never** an edit to the file | User-scope surfaces are routed, never edited. An inline marker is an in-place edit by another name |
| A registered byte-identical cluster copy | at the **canonical source**, never the copy | A marker in a copy makes it differ from its siblings and breaks the sync path |

The central record's path, keys, layering, and required fields are owned by
[`docs/conventions/finding-suppression`](../../../../../docs/conventions/finding-suppression/README.md).
It is **excluded from the scan set** — otherwise suppressing a finding changes the tree and perturbs
the next run.

| # | Assertion |
|---|---|
| 4.1 | A suppressed finding does not appear in the next run's findings, and appears in the `suppressed` section with its reason, its date, and its contributing cascade layer. |
| 4.2 | A suppression entry whose `finding_id` matches no finding is reported as **stale** rather than silently ignored. |
| 4.3 | Adding a suppression does not change any other finding's `finding_id`. |
| 4.4 | No suppression mechanism writes to a path in the derived exclusion set. Attempting to suppress a finding in a registered cluster copy makes the run refuse and name the canonical source. |

## 5. Mid-run resumability

A pass over a large corpus plus three scopes can be interrupted by compaction, a rate limit, or a
crash. Restarting from zero wastes the run and tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — never buffered to the end.
- A run manifest records, per lane: the lane id, its **input digest**, and its completion state.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash.
- **Resume** re-runs only lanes that are incomplete or whose input digest has changed. A lane whose
  digest is unchanged and whose state is complete is skipped and its findings carried forward.

| # | Assertion |
|---|---|
| 5.1 | Kill a run after lane *k* completes, resume, and the final report equals an uninterrupted run's over the same tree. |
| 5.2 | Modify one file belonging to a completed lane, then resume: that lane re-runs and no other completed lane does. |

## 6. The three tiers and their properties

The two-tier `mechanical` / `behavioral` split the delegated catalogs use cannot carry a determinism
property, for two independently sufficient reasons: no delegated check reaches the report without
model judgement (a catalog's own lane refinement and verify pass both re-judge, so even a
`mechanical`-tagged check is model-gated), and half the delegated catalog uses a different vocabulary
entirely. So the property is stated over the part of the run that genuinely is deterministic.

| Tier | Contents | Produced by | Property |
|---|---|---|---|
| **Derived** | three-scope surface inventory, exclusion set, shadowed-definition findings, raw script candidate rows | enumeration and scripts only — no model in the path | **exact equality** |
| **Judged** | every finding from a delegated catalog check, whatever that catalog calls it | a model | **stability tolerance** |
| **Delegated** | `/doctor`'s output | a prompt-based bundled skill | **none** — diffed by nobody |

The derived tier is not a consolation prize. It answers "did the pass look at the same things", which
is the question an operator asks first, and it is where a silent scope regression shows up.

Stated over two runs `R1` then `R2`; `D(R)` is the derived-tier identity set, `J(R)` the judged-tier
set.

- **P1 — determinism.** Tree unchanged ⇒ `D(R1) = D(R2)`, exactly. Not a subset, not a tolerance.
- **P2 — convergence.** Accepted fixes applied between runs ⇒ `D(R2) ⊊ D(R1)`, and every member of
  `D(R1) \ D(R2)` corresponds to a fix actually applied. A finding that vanishes without a fix is a
  defect in the check, not a success.
- **P3 — no spontaneous growth.** Tree and catalog versions unchanged ⇒ `D(R2) ⊆ D(R1)`. The set may
  grow only on a catalog version bump or a change to the tree — and a skill authored between runs is
  a change to the tree.
- **P3a — the inventory is part of the gate.** A surface that silently drops out of scope between two
  runs **fails P1**. A silent scope regression is worse than a changed finding, because it looks like
  an improvement.
- **P4 — judged-tier stability, not identity.** Judged findings are reported in their own section,
  excluded from P1–P3, and held to
  `|J(R2) \ J(R1)| ≤ max(2, ceil(0.10 × |J(R1)|))` over an unchanged tree, measured across three
  consecutive runs with the worst pair taken; and to contradicting no accepted suppression.
- **P4a — a violation has a consequence.** Exceeding the tolerance **fails the run's self-check and
  is reported as an instability finding against `audit-pass` itself**, naming the checks whose output
  moved. It is never absorbed by recalibrating the constant. The tolerance may be revised only by an
  explicit, recorded decision citing the observed distribution.
- **P5 — the delegated tier is excluded from both properties.** A prompt-based delegate cannot
  contribute to a determinism gate.

The floor of 2 exists because with a small judged set a pure percentage rounds to zero, making P4
identity by the back door — which P4 exists to deny. With a large set the percentage dominates and
the floor is irrelevant. **10% is a starting calibration, not a discovered constant.**

## 7. Report schema

Two artifacts, because incremental persistence and a sectioned report want different shapes.

**During the run — `findings.partial.jsonl`.** One JSON object per line, appended as each lane
completes. Append-only is what makes §5 real: a single JSON document would be rewritten whole on
every append, which is exactly the operation an interrupted run leaves half-done. Each record carries
its `lane`, its `tier`, the identity tuple, `finding_id`, and the rendered prose; a lane's final
record is its terminating record, which is what marks the lane complete.

**At the end — `findings.json`.** One document assembled from the partial, carrying `schemaVersion`,
the run and target identity, the resolved version of every catalog consulted, and then the sections:

| Section | Contents |
|---|---|
| `inventory` | the three-scope surface list, derived tier |
| `mechanical` | derived-tier findings, including shadowed definitions |
| `behavioral` | judged-tier findings |
| `suppressed` | every suppressed finding with its reason, date, and contributing cascade layer |
| `delegated` | `/doctor`'s output, diffed by nobody |
| `skipped` | every surface excluded, **with its reason** — a silent exclusion reads as coverage, and this section is what stops it |

**Resume reads the partial, not the report**, so completion state is derivable from the artifact
rather than tracked beside it and able to disagree with it.
