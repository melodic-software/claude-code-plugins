---
outcome: contract-defined
tier: A
date: 2026-07-24
---

# Phase 4 — the re-run contract

Task #35. Idempotence is the Brief's headline acceptance criterion, and after the proportionality
gate it carries more weight than it did: the argument for the sweep existing at all is that *the
checks are delegated but the run semantics are not*. If this document lands as prose intent, that
argument has nothing behind it. So every property below is written as a condition a test could
assert, with the assertion named.

Terms used throughout: a **run** is one invocation of the sweep against one **target**; a **lane** is
one check applied to one surface class; the **scan set** is the set of files a run reads.

## 1. Finding identity

"The same finding set" is undiffable while findings are prose judgements. Identity is a four-part
tuple, and the run emits it machine-readably.

```text
identity = (surface, check, anchor, claim)
```

- **`surface`** — the file's logical path, never a machine-absolute one. Repo-scope surfaces are
  repo-relative POSIX paths with no leading `./`. User-scope surfaces are scope-prefixed logical
  paths (`user:.claude/CLAUDE.md`), and managed-policy surfaces likewise (`managed:CLAUDE.md`), so a
  report is comparable across machines whose absolute paths differ.
- **`check`** — a fully-qualified check id, `<plugin>/<skill>/<check>`, e.g.
  `claude-config/audit-instructions/I12`. Bare `I12` is ambiguous across catalogs.
- **`anchor`** — **content-derived, never line-derived.** A line number shifts when anything above it
  changes, which would make an unrelated edit churn the whole report and destroy the property this
  contract exists to protect. The anchor is `sha256(normalized_excerpt)` truncated to 12 hex
  characters, carried alongside a human-readable heading path (`## Rules > ### Naming`) for report
  legibility only — the hash is what identity compares. Normalization: strip trailing whitespace,
  collapse internal whitespace runs to one space, strip surrounding markdown emphasis markers.
  Case is preserved, because these surfaces contain code and identifiers.
- **`claim`** — the check's canonical claim id plus its bound parameters, **not** free prose. Every
  check declares a closed set of claim templates in its criteria entry; a finding names one and
  supplies its parameters. Prose is a rendering of the claim, never the claim itself.

**`finding_id` = `sha256` of the four fields joined by `\x1f`, truncated to 16 hex characters.**

- **Assertion 1.1** — for a fixed tree, `finding_id` is stable across runs, working directories,
  operating systems, and path separators. Test: run twice from two different absolute paths on two
  path-separator conventions; the id sets are equal.
- **Assertion 1.2** — inserting an unrelated paragraph above a finding does not change its
  `finding_id`. Test: fixture with a known finding, insert 20 lines above it, re-run, id unchanged.
- **Assertion 1.3** — every emitted finding validates against the report schema, and its `claim` id
  exists in the cited check's declared template set. A finding whose claim id is not declared is a
  hard error, not a warning — that is what stops prose leaking back in.

## 2. Where the report lives

**A run never writes into its own scan set.** If run 1 writes a report into the tree, run 2's tree is
not unchanged and the idempotence property is unfalsifiable by construction.

- The report is written under `${CLAUDE_PLUGIN_DATA}`, which resolves outside any target repository
  and survives plugin updates, at `runs/<state-key>/<run-id>/findings.json` — `<state-key>` per §3.
- The operator may redirect the report into the target tree with an explicit argument. When they do,
  the run **must** add that path to the exclusion set for subsequent runs and say so in its output.
  Silently scanning your own previous report is the failure this rule exists to prevent.
- **Assertion 2.1** — after a run against a clean git worktree with no redirect argument,
  `git status --porcelain` is empty. This is the whole property in one command.
- **Assertion 2.2** — with the redirect argument, a second run's scan set excludes the redirected
  path, and the two runs' mechanical identity sets are still equal.

## 3. Run state, keying, and concurrency

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project. This machine alone carries multiple
worktrees of this repository plus a large ghq checkout root, so state keyed by working directory
would collide or fragment depending on where the operator happened to stand.

**State key.** `<state-key>` = `<repo-identity>/<worktree-discriminator>`.

- **`repo-identity`** — for a git repository, the first configured remote URL normalized to
  `host/owner/repo`, lowercased, with any `.git` suffix and credentials stripped. With no remote,
  `local/<sha256 of the canonicalized repo root>` truncated to 12.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository on different branches legitimately hold different content and must not
  share a run report.

**Suppressions are keyed differently on purpose** — see §4. They are a decision about the
*repository*, not about a checkout, so they are shared across worktrees and, where the target is a
repository the operator owns, committed to it.

**Concurrency.**

- A read-only run takes **no lock**. Concurrent read-only runs are safe and are not serialized.
- An applying run takes an **exclusive advisory lock** at `runs/<state-key>/lock`, containing the
  process id and an ISO-8601 start timestamp.
- A second applying run for the same `<state-key>` **refuses and exits non-zero** with the holder's
  pid and start time. It does not wait, because a sweep over a large tree can run for a long time and
  a silent queue looks like a hang.
- A lock whose recorded pid is not alive **and** whose timestamp is older than 30 minutes is stale
  and is reclaimed, with the reclamation reported in the run output.
- **Assertion 3.1** — two applying runs launched concurrently against one target: exactly one
  proceeds, the other exits non-zero naming the holder.
- **Assertion 3.2** — two read-only runs launched concurrently both complete, and their mechanical
  identity sets are equal.
- **Assertion 3.3** — a run launched from a subdirectory of the target produces the same
  `<state-key>` as one launched from the root. Working directory must not be an input.

## 4. Suppression, per target class

A deliberately-kept finding must not resurface. But "its site" differs by class, and one mechanism
does not fit all four. **The governing rule: an inline marker is permitted only where the pass may
write; everywhere else suppression is central and keyed by `finding_id`.**

| Target class | Suppression site | Why |
|---|---|---|
| A file in the target repo the pass may edit | inline marker at the finding's site | Local, reviewable in the same diff as the content it governs, and it travels with the content — the idiom `docs-hygiene:audit-noise` already uses |
| A `SKILL.md` or file this pass does not own | central suppression file in the target repo, keyed by `finding_id` | Editing a file you do not own to silence a report is a boundary violation dressed as configuration |
| A chezmoi-managed `~/.claude/**` file | central, in the user-scope suppression record; **never** an edit to the file | The Brief settles that user-scope surfaces are routed, never edited. An inline marker would be an in-place edit by another name |
| A registered byte-identical cluster copy | at the **canonical source**, never the copy | An inline marker in a copy makes it differ from its siblings and breaks the sync path — the same failure the exclusion set exists to prevent |

**The central suppression record** lives at a documented path in the target repository, carries one
entry per suppressed `finding_id` with a required free-text reason and the date, and is **excluded
from the scan set** — otherwise suppressing a finding changes the tree and perturbs the next run.

- **Assertion 4.1** — a suppressed finding does not appear in the next run's report, and appears in a
  `suppressed` section with its reason, so suppression is visible rather than silent.
- **Assertion 4.2** — a suppression entry whose `finding_id` no longer matches any finding is
  reported as **stale** rather than silently ignored. A suppression that has outlived its finding is
  how a corpus quietly loses a check.
- **Assertion 4.3** — adding a suppression does not change any other finding's `finding_id`.
- **Assertion 4.4** — no suppression mechanism writes to a path in the derived exclusion set. Test:
  attempt to suppress a finding in a registered cluster copy; the run refuses and names the canonical
  source instead.

## 5. Mid-run resumability

A run over 181 skills plus three scopes can be interrupted by compaction, a rate limit, or a crash.
Restarting from zero wastes the whole run and, worse, tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — not buffered to the end.
- A run manifest records, per lane: the lane id, its **input digest**, and its completion state.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash.
- **Resume** re-runs only lanes that are incomplete or whose input digest has changed. A lane whose
  digest is unchanged and whose state is complete is skipped and its findings are carried forward.
- **Assertion 5.1** — kill a run after lane *k* completes, resume, and the final report equals the
  report of an uninterrupted run over the same tree. This is the property; everything else in §5 is
  mechanism.
- **Assertion 5.2** — modify one file belonging to a completed lane, then resume: that lane re-runs
  and no other completed lane does.

## 6. The idempotence properties

Stated as assertions over two runs, `R1` then `R2`. `M(R)` is the mechanical-tier identity set;
`B(R)` is the behavioral-tier set.

- **P1 — determinism.** Tree unchanged between `R1` and `R2` ⇒ `M(R1) = M(R2)`, exactly. Not a
  subset, not a tolerance: equal.
- **P2 — convergence.** Accepted fixes applied between `R1` and `R2` ⇒ `M(R2) ⊊ M(R1)`, and every
  member of `M(R1) \ M(R2)` corresponds to a fix that was actually applied. A finding that vanishes
  without a fix is a defect in the check, not a success.
- **P3 — no spontaneous growth.** Tree unchanged and catalog version unchanged ⇒ `M(R2) ⊆ M(R1)`. The
  set may grow only on a catalog version bump or a change to the tree — and a skill authored between
  runs is a change to the tree.
- **P4 — behavioral stability, not identity.** Behavioral-tier detection is a model judgement and
  cannot be made deterministic; an identity function normalizes how a finding is *reported* and
  cannot make the *detection* reproducible. So behavioral findings are reported in a separate
  section, excluded from P1–P3, and held instead to:
  - `|B(R2) \ B(R1)| ≤ max(2, ceil(0.10 × |B(R1)|))` over an unchanged tree — **the stated
    tolerance**, measured across three consecutive runs, with the worst pair taken;
  - no member of `B(R2)` contradicts an accepted suppression.
- **P5 — `/doctor` is excluded from both tiers.** It is prompt-based rather than fixed logic, so it
  cannot contribute to a determinism gate, and its output is reported in its own section and diffed
  by nobody.

**Why the tolerance is a floor of 2 rather than a pure percentage.** With a small behavioral set, a
percentage rounds to zero and the property becomes identity by the back door — which P4 exists to
deny. With a large set, the percentage dominates and the floor is irrelevant. The number is a
starting calibration, not a discovered constant: Phase 10's dogfood run is what tests whether 10% is
the right figure, and the figure is expected to move once there is evidence.

## Sanity check

The Phase 4 sanity check asks that this document state the identity tuple, the report location rule,
the state key, the concurrency posture, the per-class suppression surface, the checkpoint property,
and each idempotence property **as a condition a test could assert — not as prose intent**. Each is
above under a numbered assertion. The count is 5 identity/report/state assertions, 4 suppression
assertions, 2 resumability assertions, and 5 idempotence properties.

**What this document deliberately does not decide.** The report's concrete schema, the suppression
file's path and format, and the lane decomposition are Phase 6 design, because they depend on the
sweep's dispatch structure. This document constrains them; it does not specify them.
