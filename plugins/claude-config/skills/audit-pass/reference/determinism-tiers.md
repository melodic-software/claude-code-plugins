# audit-pass — the three tiers and their properties

This file owns §6: the derived, judged, and delegated tiers, the comparability predicate they are
stated over, and properties P1–P6 with the determinism gate that measures their precondition.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

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

### The precondition must be measured, not assumed

Every property below is conditioned on "tree unchanged". **A run cannot assume that precondition of
itself.** The state key is computed once at Phase 0, and nothing re-validates the tree at Phase 6, so
a checkout that moves *during a single run* — another session switching branches, pulling, or
committing underneath it — yields a comparison whose basis silently stopped holding. This is not
hypothetical: a pass over a shared checkout observed its target move mid-measurement, from one commit
on one branch to a different commit on another, with a rename landing in between. Several concurrent
sessions on one repository is the normal case for the operator who runs this first.

So the run **measures** its own precondition:

- At the **scan baseline** — Phase 1's inventory frozen, before any lane reads — and again at the
  **audit endpoint** — the moment the last lane completes, *before* any Phase 5 mutation — capture the
  target's **HEAD commit** and the run's **state digest**.
- **State digest** = `sha256` over the inventoried surfaces in sorted order, each paired with the
  content hash of its current bytes, plus every dirty path in the target worktree on the same terms —
  path set from **`git status --porcelain --untracked-files=all`**, content hash from
  `git hash-object`, a deleted path paired with a fixed deletion sentinel.
- **`--untracked-files=all` is required, not a preference.** Bare `git status --porcelain` collapses
  an untracked directory to a single `?? dir/` entry rather than listing its files, and
  `git hash-object` on a directory fails — so on the ordinary worktree state of having one untracked
  directory, the baseline digest cannot be computed at all and the determinism gate does not merely
  degrade, it fails to run. `all` yields file paths, which is what the digest hashes. Parse the
  porcelain **paths**, not the status letters: a rename entry carries `orig -> new` and a path with
  unusual bytes is emitted quoted, so both need decoding before hashing. Prefer `-z` where available,
  which sidesteps the quoting entirely.
- **Its scope is every inventoried scope, not the target repository alone.** Restricting it to the
  target worktree leaves the user-global and managed-policy surfaces outside the measurement, and
  those are read by the lanes exactly like project files: editing `~/.claude/CLAUDE.md` between runs
  can move derived script candidates and dead-surface classifications while HEAD and the target's
  dirty set both hold still. The gate would then report a legitimate external-state change as a
  determinism **defect** rather than `indeterminate` — an accusation instead of an abstention, which
  is the worse of the two errors. If Phase 1 inventoried a surface, the digest covers it.
- **A count is not enough:** editing a dirty file's contents, or swapping
  one dirty path for another, leaves both HEAD and the count identical, so a count-based gate would
  evaluate P1–P3 as though the tree held still while different lanes in fact read different states.
  Pairing each path with its content is what makes both movements visible.
- **The run's own artifacts are excluded from the digest, on the same list that excludes them from
  the scan.** A report path inside the target appears in `git status --porcelain` the moment the report
  is written, which is between the scan-baseline and audit-endpoint captures — so a digest over *every*
  dirty path makes that run fail its own determinism gate as `indeterminate`, every time, purely
  because it did what it was asked to do. Recording the path in the scan exclusion set does
  not reach the digest; the exclusion has to apply to both, and it is one list precisely so the two
  cannot diverge. **The exclusion is keyed on containment, not on `--report-to`** — Class 4's predicate
  is `write_path ⊆ target_root`, so it covers the default `${CLAUDE_PLUGIN_DATA}` path just as well
  whenever the target sits at or above `~`. Keying it on the flag was the defect that made every run
  against such a target report `indeterminate` about itself. What is excluded is the pass's own class-4
  artifact set and nothing else: a *different* file appearing or changing is still a moved tree and
  still `indeterminate`.
- If either capture differs, the determinism gate is reported **`indeterminate`**, never `passed` and
  never `failed`, naming both captures and what moved.
- **Two endpoint captures detect a net change, not a transient one.** A file mutated and reverted
  inside the run is invisible to them. §5's per-lane input digests narrow that: two lanes whose
  inputs overlap record content hashes for the shared paths, and a disagreement between them means
  the tree moved mid-run, reported `indeterminate` on the same grounds — the lanes demonstrably did
  not read one state.

  **Narrows, not closes, and the residue is stated rather than left implied.** A file changed and
  restored between two samples hashes identically at both, and a file read by only one lane has no
  cross-lane comparison at all — so a lane can read transient bytes and every recorded hash still
  agree. Two mitigations, both bounded: each lane samples its inputs **immediately before and
  immediately after its own reads** and reports `indeterminate` for itself when its own pair
  disagrees, which shrinks the undetectable window from the whole run to one lane's read span; and
  the run states in its report that detection is **sampling-based**, so a mutation entirely inside a
  sampling gap is not detected.

  Closing it completely needs the lanes to read from an **immutable snapshot** — a `git worktree` of
  the recorded revision, or a filesystem snapshot — which is a real option and not one this contract
  mandates, because it cannot cover the untracked and user-scope surfaces the scan set includes. What
  is binding is the honesty: the gate detects a tree that moved *across* samples and says so, and it
  does not claim to detect one that moved *between* them.
- `indeterminate` is a distinct outcome, not a soft pass. It says the run could not establish the
  basis for the comparison — which is a true statement — where `passed` would assert a stability that
  was never tested.

An unfalsifiable `passed` is worse than an honest `indeterminate`: it manufactures confidence out of
a precondition nobody checked, and it is indistinguishable in the report from a gate that genuinely
held.

Every property below is conditioned on the runs being **comparable**, stated here once rather than
per-property so the clause cannot drift between them:

> `R1` and `R2` are **comparable** when their **scan-baseline state digest**, **live surface set**,
> **observable detection version** of every check consulted, **harness version**, and
> **behavior-affecting arguments** are all equal.

**Observable detection version** is what the pass can actually establish without reading inside
another plugin, and it has two forms per check:

- **Qualified** — the invocation declared its catalog version and prompt digest. Those are the
  values compared, and a catalog edit is detected exactly.
- **Unqualified** — it declared neither, the state of every delegated catalog today. The compared
  value is then what is observable from outside: the delegate plugin's **semver from the marketplace
  manifest**, plus the harness version. The comparison is **coarse** and the report says so per
  check, because a catalog edit that ships without a version bump is invisible to it.

**Defining it as "the catalog version and prompt digest" made every property vacuous, and that was
the defect.** If the compared values cannot be established, no pair is ever comparable, so P1–P4
assert nothing about any two real runs — the resume fallback stopped a *resumed* report from mixing
configurations, and did nothing for the cross-run comparison, which is a different question with the
same cause. An unknown sentinel compared equal to itself would have been worse: it reads as a clean
comparison while missing exactly the catalog changes the input exists to catch.

Coarse-but-honest is the right trade here because the failure directions are not symmetric. A missed
sub-semver catalog edit makes a property assert over a pair it should have abstained on — one wrong
finding, visibly attributed to a named check. Vacuity makes every property assert nothing, silently,
forever. The report names each unqualified check so the coarseness is attributable rather than
assumed, and the exact comparison arrives for free the moment a delegate declares its detection
version — the same declaration `claim` templates already ask of it.

**Behavior-affecting arguments belong here too, not only in the resume digest.** Two completed runs
differing only in `--opinion` were classified comparable while one deliberately ran additional
checks, so the extra judged findings could fail P4 as audit instability — a false alarm produced by
the operator using a documented flag.

**The first input is the state digest, not the target tree, and the difference is the whole point of
widening the digest.** "Target tree" covers only the repository, so a changed `~/.claude/CLAUDE.md`
or managed-policy file left two runs classified as comparable while their derived sets legitimately
differed — reported as a determinism **defect**, the accusation-instead-of-abstention failure the
widened digest was introduced to close, surviving in the cross-run definition after being fixed in
the within-run one. Since the state digest already spans every inventoried scope and the target's
dirty set, and the baseline is taken with the inventory frozen, comparing baselines compares exactly
what the lanes were about to read. This is what makes eval 22's `indeterminate` the contract's answer
rather than an assertion against it.

A property asserts nothing about a non-comparable pair, which is reported as **non-comparable naming
the input that moved** — never as a pass and never as a failure. This is not a hedge: each input
changes what a *correct* run finds, so comparing across one makes correct behavior indistinguishable
from a defect, in the false-alarm direction. The live surface set earns its place the same way —
startup scope depends on the launch directory, the additional-directory set, and settings the tree
does not contain, so two runs over a byte-identical tree can legitimately see different surfaces. A
detection-behavior input not covered by the digest is a defect in the digest.

- **P1 — determinism.** `R1` and `R2` comparable ⇒ `D(R1) = D(R2)`, exactly. Not a subset, not a
  tolerance. **A comparability change is reported as the cause and never silently absorbed** — a run
  that quietly attributed a liveness or version difference to the tree, or to nothing, would be the
  same silent scope regression P3a exists to catch.
- **P2 — convergence, measured against the findings the fixes targeted.** P2 is the one property
  whose whole subject is a *changed* tree, so it takes the comparability relation **modulo the
  accepted mutation set**: `R1` and `R2` are **fix-comparable** when every comparability input is
  equal *except* for the differences **attributable to the edits accepted in `R1`** — no more.
  Stated separately because the unqualified relation excludes precisely the pair P2 exists to judge,
  which would leave the convergence property unevaluable in the normal case; and *"no more"* is what
  keeps it a real constraint rather than a hole, since any difference not attributable to the
  accepted set means something else moved and P2 abstains exactly as P1 would. The applied-set
  comparison the mutation-integrity capture already performs is what makes the delta checkable.

  **The exemption covers the live surface set too, not the state digest alone.** Exempting only the
  tree would have re-broken P2 on the fix the delegated catalogs most often recommend: moving
  always-loaded material into a skill changes what is loaded at startup, so the accepted remediation
  moves the live surface set as a *consequence*, and P2 would abstain on exactly the remediation it
  is supposed to verify. Attribution is what bounds this — a surface entering or leaving the live set
  because an accepted edit created, deleted, or moved it is attributable; one that moved because the
  launch directory or `claudeMdExcludes` changed is not, and P2 abstains.

  Fix-comparable ⇒ every finding a fix targeted is absent from R2, and **every derived addition in
  `D(R2) \ D(R1)` is attributable to an accepted edit**.

  **An unconditional subset form rejects the remediation this relation is written to admit.** Moving
  material out of `CLAUDE.md` into a newly created skill makes `D(R2)` gain that skill's own
  inventory identity — a derived *addition* — so `D(R2) ⊆ D(R1)` fails even though the entire delta
  traces to the accepted edit. Fixing comparability without also conditioning the subset assertion
  leaves the defect in place. The condition is therefore attribution, exactly as comparability
  is: additions the accepted edit accounts for are expected, and a **non-attributable** addition is
  the real failure — that is spontaneous growth during a fix round, which is P3's concern arriving
  through the convergence door.
  **Strictness is conditional and is stated as removal, not as a subset:** when at least one accepted
  fix targeted a derived-tier finding, that finding must be **absent** from `D(R2)`. A judged-tier
  fix need remove nothing from `D` — rewriting an over-prescriptive instruction leaves the surface
  inventory, the exclusion set, the shadowed definitions, and the raw script-candidate rows exactly
  as they were — so a blanket requirement would declare a perfectly good fix non-convergent, which is
  the wrong verdict on the commonest fix there is.

  **`D(R2) ⊊ D(R1)` is the wrong shape even conditionally, because a proper subset forbids
  additions that the attribution rule above explicitly permits.** Resolving a derived
  shadowed-definition finding by renaming one of the two definitions removes the targeted finding
  *and* adds that renamed definition's inventory identity — attributable, expected, and fatal to any
  subset formulation. What convergence actually claims is that **the targeted findings are gone**,
  which is a statement about specific findings rather than about set cardinality; additions are
  already governed, one clause above, by attribution. Conversely, a finding that vanishes without a fix is a defect in the check,
  not a success. **Its detector is §4's fourth disposition**: every disappearance is accounted for as
  a fix, a successor, or an UNEXPLAINED DISAPPEARANCE that fails the self-check. Without that
  accounting P2 is a definition nothing can observe.
- **P3 — no spontaneous growth.** `R1` and `R2` **comparable** ⇒ `D(R2) ⊆ D(R1)`. The set may grow
  only on a change to one of the comparability inputs — a detection or harness version bump, a moved
  liveness basis, a different behavior flag, or a change to the tree, and a skill authored between
  runs is a change to the tree. P3 stated its own shorter list ("tree and catalog versions") until
  the comparability predicate was introduced; the enumeration is exactly the negation of
  comparability, so it is cited rather than restated — restating it is what let P1 and P4a drift.
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
- **P6 — an unestablished precondition yields `indeterminate`.** A run whose start and end captures
  of HEAD and state digest disagree — or whose per-lane input digests disagree on a shared path —
  reports the determinism gate as `indeterminate` and does not
  evaluate P1, P2, or P3 for that pair. Their precondition demonstrably did not hold, so a verdict on
  them would be an assertion about a comparison the run never actually made.

| # | Assertion |
|---|---|
| 6.1 | A run captures HEAD and the state digest at the **scan baseline** (Phase 1 inventory frozen, before any lane reads) and again at the **audit endpoint** (last lane complete, before any Phase 5 mutation), and records both captures in the report. |
| 6.1c | The scan baseline covers every surface the Phase 1 inventory produced, including user-scope and managed-policy surfaces — it is not computable before that inventory exists. |
| 6.1a | A `--fix` run that applies at least one accepted edit against an otherwise-unchanging tree reports the determinism gate as satisfied, not `indeterminate` — its own accepted mutations fall outside the measured read window. |
| 6.1b | Editing an inventoried user-scope surface (`~/.claude/CLAUDE.md`) mid-run yields `indeterminate`, even though the target's HEAD and dirty set are both unchanged. |
| 6.2 | When the two captures differ, the determinism gate reads `indeterminate` — never `passed`, never `failed` — and names both captures and what moved. |
| 6.2a | Changing a dirty file's contents during a run, or replacing one dirty path with another, changes the state digest and yields `indeterminate`, even though HEAD and the number of dirty files are unchanged. |
| 6.2b | Two lanes whose inputs overlap record the same content hash for every shared path; a disagreement yields `indeterminate`. |
| 6.3 | An `indeterminate` gate is visibly distinct from a passing one in the report, and P1–P3 are reported as not evaluated rather than as satisfied. |

The floor of 2 exists because with a small judged set a pure percentage rounds to zero, making P4
identity by the back door — which P4 exists to deny. With a large set the percentage dominates and
the floor is irrelevant. **10% is a starting calibration, not a discovered constant.**
