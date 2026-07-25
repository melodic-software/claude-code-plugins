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

### The tiers had to be re-derived first — the two-tier split did not survive contact

The original two tiers came from the `audit-instructions` catalog: `mechanical` (pattern-detectable
by static reading) and `behavioral` (ground truth is observed model behavior). The determinism
property was defined over the mechanical tier. **Verified against the implementations, that split
cannot carry it**, for two independently sufficient reasons.

- **No dispatched check reaches the report without model judgment.** `audit-instructions`' own
  `SKILL.md` says the deterministic pre-scan "is advisory and a grep cannot judge whether a
  rationale is genuinely present, so the lane refines every candidate rather than reporting it
  verbatim" — and Phase C then re-judges *every* removal or rewrite proposal, not only behavioral
  ones, where "a proposal the verifier defends is demoted to `info` or dropped." So a check the
  catalog labels `mechanical` passes through two model stages before it is a finding. Two runs can
  differ on a borderline case from ordinary sampling variance.
- **Half the dispatched catalog has no tier at all.** `claude-memory`'s `reference/criteria.md`
  carries **17 checks and zero occurrences** of `mechanical` or `behavioral`; it labels
  `FAIL`/`WARN`/`INFO`. A property defined over a vocabulary that half the catalog does not use is
  undefined for that half.

**Three tiers, replacing two.** The fix is not to weaken the guarantee everywhere — it is to state
it over the part of the run that genuinely is deterministic, which turns out to be substantial and
was previously unnamed.

| Tier | What it contains | Produced by | Property |
|---|---|---|---|
| **Derived** | the three-scope surface inventory, the exclusion set, shadowed-definition findings, and raw script candidate rows | scripts and enumeration only — no model in the path | **exact equality** |
| **Judged** | every finding from a dispatched catalog check, whatever that catalog calls it | a model, through lane refinement and the Phase C verifier | **stability tolerance** |
| **Delegated** | `/doctor`'s output | a prompt-based bundled skill | **no property**, diffed by nobody |

The derived tier is not a consolation prize. It is the answer to "did the sweep look at the same
things", which is the question an operator actually asks first — and it is where a silent scope
regression would show up. A surface that vanished from the inventory between runs is a defect the
old two-tier split could not have caught, because the inventory was never a reported artifact.

**Consequence for the deliverable, stated plainly.** D1 is a judged finding, so the deliverable's
primary check does not contribute to the diff-clean gate. That was already conceded; what is new is
that *no* catalog check contributes, so the concession is not specific to D1 and is not evidence
against it.

### The properties

Stated as assertions over two runs, `R1` then `R2`. `D(R)` is the derived-tier identity set; `J(R)`
is the judged-tier set.

- **P1 — determinism, over the derived tier.** Tree unchanged between `R1` and `R2` ⇒
  `D(R1) = D(R2)`, exactly. Not a subset, not a tolerance: equal. This is assertable because nothing
  in `D` passes through a model — it is file enumeration, registry parsing, `git worktree list`, and
  name comparison across a fixed precedence order.
- **P2 — convergence.** Accepted fixes applied between `R1` and `R2` ⇒ `D(R2) ⊊ D(R1)`, and every
  member of `D(R1) \ D(R2)` corresponds to a fix that was actually applied. A finding that vanishes
  without a fix is a defect in the check, not a success.
- **P3 — no spontaneous growth.** Tree unchanged and **detection version** unchanged ⇒
  `D(R2) ⊆ D(R1)`. The set may grow only on a detection-version bump or a change to the tree — and a
  skill authored between runs is a change to the tree.
- **P3b — "catalog version" was the wrong version, and it left a hole.** Raised by the cross-vendor
  review. P3 originally keyed on `criteria.md`'s version, which covers only the criteria file. **The
  detection behavior for checks I6 and I10 does not live there.** It lives in
  `audit-instructions`' `SKILL.md`: Phase B names the pre-scan script that emits the I6 and I10
  candidate rows and instructs the lane that the script "is advisory and a grep cannot judge whether
  a rationale is genuinely present, so the lane refines every candidate rather than reporting it
  verbatim"; Phase C prompts the verifier to refute with a specific question and demotes or drops
  what it defends. Both are prompt text, and **`SKILL.md` carries no version at all.** Rewording
  either — tightening the refutation prompt, changing what "refines" means — moves the finding set
  with `criteria.md`'s version untouched, so P3 would report no growth was licensed while growth
  occurred. The same hole exists for the script itself, which is also unversioned.

  **Fix: P3 keys on a composite detection version, not on a catalog version.** For each dispatched
  check the run records a `detectionVersion` triple:

  ```text
  detectionVersion = (catalog_version, host_plugin_version, prompt_digest)
  ```

  - **`catalog_version`** — the criteria file's own version, as today.
  - **`host_plugin_version`** — the semver in the owning plugin's `.claude-plugin/plugin.json`. This
    is the seam that already exists and already moves: the repo requires a manifest bump plus a
    matching changelog heading for a content change, so editing `SKILL.md` prompt text is *already*
    a version event. P3 simply has to read that version instead of ignoring it.
  - **`prompt_digest`** — `sha256` over the check's own detection-behavior inputs, truncated to 12:
    the host `SKILL.md` and any script it names for that check. It exists because the manifest bump
    is a **convention** enforced by review, not a mechanism enforced by the file's own bytes; a
    prompt edit that skips the bump is exactly the silent case P3 must catch. The digest fails
    closed where the convention fails open.

  A growth in `D` is licensed when any component of the triple changed, and is a **P3 violation
  reported against the sweep** when none did. The composite is recorded per check in the report's
  existing per-catalog version block, so a diff of two reports shows which component moved.

  **Two consequences, stated rather than left implicit.** The digest makes an unrelated `SKILL.md`
  edit — a typo in a Gotchas line — read as a licensed-growth event, which is a false *permission*
  rather than a false alarm: it lets a real spontaneous growth pass unreported that run. That is the
  correct direction to fail, because the alternative silently blesses prompt rewrites. And the
  triple is the reason task **#43** (machine-readable versioning for the catalog) is necessary but
  not sufficient — versioning `criteria.md` alone does not close this; the plan item should carry
  both halves.
- **P3a — the inventory is part of the gate, not scaffolding for it.** The derived tier includes the
  three-scope surface inventory and the exclusion set, so a surface that silently drops out of scope
  between two runs **fails P1**. This is the property the old two-tier split could not express,
  because the inventory was never a reported artifact — and a silent scope regression is worse than a
  changed finding, since it looks like an improvement.
- **P4 — judged-tier stability, not identity.** Judged detection is a model judgement and cannot be
  made deterministic; an identity function normalizes how a finding is *reported* and cannot make the
  *detection* reproducible. So judged findings are reported in a separate section, excluded from
  P1–P3, and held instead to:
  - `|J(R2) \ J(R1)| ≤ max(2, ceil(0.10 × |J(R1)|))` over an unchanged tree — **the stated
    tolerance**, measured across three consecutive runs, with the worst pair taken;
  - no member of `J(R2)` contradicts an accepted suppression.
- **P4a — a violation has a consequence, or the property is decoration.** Exceeding the tolerance
  **fails the run's self-check and is reported as an instability finding against the sweep itself**,
  naming the checks whose output moved. It is not silently absorbed by recalibrating the constant.
  The tolerance may be revised only by an explicit, recorded decision citing the observed
  distribution — never as an implicit response to a failure. Without that clause the metric absorbs
  its own counterevidence, which is what a placeholder does.
- **P5 — `/doctor` is the delegated tier and is excluded from both properties.** It is prompt-based
  rather than fixed logic, so it cannot contribute to a determinism gate, and its output is reported
  in its own section and diffed
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
assertions, 2 resumability assertions, and 8 idempotence properties — P1, P2, P3, P3a, P3b, P4, P4a,
P5.

**What this document deliberately does not decide.** The report's concrete schema, the suppression
file's path and format, and the lane decomposition are Phase 6 design, because they depend on the
sweep's dispatch structure. This document constrains them; it does not specify them.
