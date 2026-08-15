# Persisting survivors — this plugin's read of the detector-findings contract

The mechanics of `--persist-findings` (SKILL.md "Phase 6 — Persist (opt-in)").

**Read the producer contract before the first write** —
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what a
mutation run decides for itself, and cites the contract for the rest. Where the two disagree, the
contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard could
not be resolved from their owner, and stop. Inventing a destination is the one failure the contract's
own resolution section exists to prevent, and a plausible guess is worse than no file: the run
reports success while the consumer never scans that path.

## Where the file goes

Resolve the destination and run the guards per the contract "Where the file goes". Three of its
obligations are the ones a mutation run is most likely to skip, so they are named — not restated —
here: run the **whole** rung order rather than its last rung; take the **non-interactive collapse**
for the rungs that confirm or ask, since a headless detector cannot answer; and honor the
**self-ignore guard**, including the invalid-root rule that keeps it out of a consumer's root
`.gitignore`.

File name: `${TS}-mutation-survivors.md`, with `TS="$(date -u +%Y%m%dT%H%M%SZ)"` — colon-free and
Windows-safe, so lexical sort equals chronological sort.

**Never overwrite an existing path.** When `${TS}-mutation-survivors.md` already exists, write
`${TS}-mutation-survivors-2.md`, then `-3`, taking the smallest free integer ≥ 2. Two runs inside the
same second is the ordinary cause, and overwriting would destroy a file this producer had already
handed to the merge set — the same defect as writing into a file another producer owns.

## Prove the destination is outside tracked space before writing to it

This phase makes **two** writes — the findings file and, when the self-ignore guard heals a root, that
root's `.gitignore` — and the property to prove is that git picks up neither. Both are proven before
either happens, and the order is what makes that true:

1. **Find the governing checkout by walking the resolved root's ancestors** for a `.git` entry:
   `test -e <ancestor>/.git`, with `-e` and not `-d`, because a worktree's `.git` is a file. The first
   ancestor that has one is the checkout `T` governing the destination. If none does, **no checkout
   governs the path** — nothing can track anything beneath it, and both writes proceed. A `.git`
   that is present but unusable — dangling `gitdir:`, a bare repository, or the destination sitting
   inside a checkout's own `.git/` — is **not** an absence: `T` was found, so steps 3 and 5 run and
   refuse on the non-zero exit git returns. Only "no ancestor has one" is the permissive branch.
2. **Reject a root-equivalent `memory_dir`** — the contract's invalid-root rule, judged against `T`
   rather than the invoking worktree, since a root that is *another* checkout's toplevel would heal
   into *that* repo's root `.gitignore`.
3. **Prove the guard's write before the guard makes it:** `git -C T ls-files -- <the resolved root>`
   must list **nothing**. A memory root holding tracked files is a source directory, and healing `*`
   into it rewrites the ignore semantics of files the consumer owns. Stop there, before anything is
   created — this step, not a later report, is what keeps the guard's write inside the proof.
4. **Run the self-ignore guard**, then create the destination directory.
5. **Prove the findings file:** `git -C T check-ignore -q -- <the exact intended file path>`, and
   **write only on exit 0.**

**Why a filesystem walk in step 1 and not `git rev-parse --show-toplevel`.** `rev-parse` fails
identically — exit 128 — for "there is no repository", for "that directory does not exist", and for a
discovery limit such as `GIT_CEILING_DIRECTORIES` under which a repository *does* govern the path.
Reading any non-zero as "no repository" would be fail-open at the one step that decides whether the
rest of the proof is needed. The walk has no ambiguous state, needs no directory to exist yet — which
is why steps 2 and 3 can run before anything is created — and cannot be narrowed by the environment.
It is not a path-prefix comparison either: that would need canonicalized paths, and both `realpath`
and `readlink`'s canonicalizing flag are GNU-only.

**Anchor steps 3 and 5 to `T`, never to the invoking worktree.** A `memory_dir` resolving outside the
worktree is a supported configuration the consumer handles explicitly (`fix-pass-mode.md` "Step 1",
the shared-findings-directory bullet), and `git check-ignore` on a path outside its repository is
`fatal: … is outside repository`, exit 128 — so a worktree-anchored probe can never succeed there,
and `--persist-findings` would refuse every write in precisely the layout the consumer supports.
Anchoring to `T` also answers the case the invoking worktree cannot see at all: an external root that
sits inside *another* checkout, whose tracked space is just as real. Clear `GIT_DIR` and
`GIT_WORK_TREE` from both probes' environment: either one set points git at a repository other than
`T`, so the probe would answer truthfully about the wrong tree — the one failure mode `-C` alone does
not close.

**Three outcomes at step 5, and three distinct reports.** Exit 0 writes. Exit 1 means *the
destination is tracked space*, and is reported as that. Any other exit means *the probe did not
evaluate this path*, and is reported as that, quoting the resolved path and the exit status. Both
non-zero cases refuse — fail closed, because a probe that did not answer is never permission — but
reporting an undetermined probe as "tracked space" sends the reader after a repair that does not
exist. Collapsing those two states is what let a worktree-anchored probe pass for a working proof.

Step 5 is positive, and the distinction matters because the obvious alternative is worthless: a
`.gitignore` whose content is `*` matches **itself**, so a resolved root inside tracked space leaves
`git status --porcelain` byte-identical to the Phase 0 snapshot whether the write was ignored or not.
Comparing porcelain before and after therefore cannot detect the failure it appears to test.

Three states these steps catch that reasoning about the guard alone does not — and **which step
catches which** is the part to keep straight, because the guard heals between them:

- **Step 3.** A `memory_dir` or `CLAUDE.md`-declared location resolving **inside a tracked tree and
  holding tracked files**. The invalid-root rule rejects a root-*equivalent* value, not every tracked
  one, so this resolves legally. Step 5 cannot catch it — by the time step 5 runs the guard has
  written `*` there, so `check-ignore` exits 0 and `git status` is empty. Nothing is left visible to
  git, which is exactly why only a check *before* the heal sees it at all.
- **Step 5.** A resolved root whose `.gitignore` **exists but does not ignore the file** — the guard
  creates one only when absent, so a present-but-narrower file is a state no creation step reaches.
- **Step 5.** Any consumer-side ignore rule that **re-includes** the path (a later negation pattern),
  which no amount of writing `*` at the root of the memory tier overrides.

The guard's `.gitignore` is the only write this phase makes outside the findings file, and step 3 is
what proves it rather than disclosing it. Step 3 cannot be folded into step 5: on a fresh root the
guard's file is exactly what makes step 5 pass, so a single probe after the guard would be testing a
state the guard had already created. Step 5 can still refuse after the guard has healed — a consumer
negation re-including the path is that case — and such a refusal reports the guard's write alongside
it rather than leaving it behind unannounced.

## What each cell says

- **`branch:`** is `git branch --show-current` **verbatim**, never the directory slug — the contract's
  "the directory never proves ownership" obligation, which the frontmatter is what discharges.
- **`Location`** is the mutated node as `<repo-relative path>:<line>`, never the file alone. The line
  is what keeps two survivors in one file two rows rather than one merged gist.
- **`Surface(s)`** is `mutation-testing:audit` — the contract's self-naming obligation, so a collapsed
  row stays legible about who contributed it.
- **`Finding`** states the mutation and the outcome: the operator, the before → after fragment, and
  that the covering tests still passed. Neither `Finding` nor `Action` carries the Phase 4 reviewer's
  reasoning — the row is the artifact, not the argument for it.
- **`Action` names the covering test file.** Phase 1 already selected and cached the covering tests,
  so this producer *knows* the path, and withholding it is pure information loss. Write the `Action`
  as the assertion to add **and** the file to add it to.
- **Cell-escape `Finding` and `Action`** per the shape's rule. Calling it out is not redundant here:
  a mutation is a code fragment, and relational-operator inversion, boolean-connective mutants, and
  shell-pipeline removals all carry literal `|`, so this producer meets the rule on nearly every row
  rather than occasionally.

**Every cell describes a mutant this run actually executed.** Never compose an illustrative row, and
never carry a `Location` forward from a previous run — a fabricated row at a real `file:line` fences
a fix to code that has nothing to do with the finding, and it is indistinguishable from a real one to
everything downstream.

### Known limitation — the remediation site is not the finding site

`Location` is the mutated node, while the missing assertion belongs in the test that covered it, a
different file. A consumer that fences each remediation to its finding's `Location` therefore cannot
reach this producer's target, and naming the target in `Action` prose makes that conflict explicit
rather than resolving it — a prose cell is not a fence input. **Do not work around it here:** never
retarget `Location` at the test file to make the fence fit (it would destroy the row's identity and
its cross-producer dedup key), and never invent a column the shape does not define.

This pilot surfaced the gap; the disposition is routed to the findings-crosswalk work
(`melodic-software/claude-code-plugins#2681`), which owns it. Until that lands, treat a
mutation-survivor row as one a human dispositions.

## Tier and Confidence are computed from the verdict class

Phase 4 assigns every survivor exactly one class, and the class alone decides the row. Nothing in the
finding's prose does:

| Phase 4 class | Row | `Tier` |
|---|---|---|
| **Productive** | emitted | IMPORTANT |
| **Unclassified** — equivalence claimed with no demonstration | emitted | IMPORTANT |
| **Arid** | **none** | — |
| **Equivalent** | **none** | — |

- **Productive is IMPORTANT, not CRITICAL.** The tiers are decided by test, first match winning, and
  CRITICAL's test has three limbs — a concrete input, a caller, or a subsequent otherwise-correct
  change that the defect makes produce a wrong result. A survivor satisfies none of them: it
  demonstrates that *the suite* fails to detect a change, not that any input, caller, or future edit
  produces a wrong result. The third limb is the near miss and still fails, because the defect it
  needs is one in the source, and a survivor is evidence about the tests. IMPORTANT's test then
  matches in the survivor's own words — behavior no test covers.
- **Unclassified ranks with productive, not below it.** Reaching for "equivalent" is the standard way
  this technique manufactures false confidence (see Gotchas), so ranking an undemonstrated
  equivalence claim beneath a demonstrated gap would let the claim bury the finding.
- **Arid emits no row** — not because it is unimportant, but because its only remediation is a
  suppression entry this skill proposes and never writes unprompted, accepted by the user per
  "Remediation — delegated". Handing it to an apply relay would launder that consent gate. Phase 5
  still shows every arid survivor and its proposed entry to the human, so the human loses nothing.
- **Equivalent emits no row.** It is not a defect; emitting it would manufacture a finding.

**The map is deliberately flat.** Every emitted row makes the same claim — behavior no test covers —
so every emitted row carries the same tier. Manufacturing a spread would mean re-deriving tier from
the finding's prose, which is exactly what a class-keyed map exists to prevent. Where the consuming
project defines its own severity vocabulary, the contract's precedence rule binds this producer too:
map to the project's tiers, with the baseline value above as the fallback.

**`Confidence` is `high` on every emitted row.** Phase 3 executed the mutant and recorded its state,
so each row cites an executed mutant, and the contract's omission branch — for a producer that fired
on a pattern it never verified — does not arise. `low` is never emitted, per the contract's
`high`-or-omitted rule.

## When the file is written at all

**A failed restore precedes this question and is not one of its answers.** A run that could not verify
a revert ended in failure at Phase 3, so this phase is unreachable and nothing below applies to it —
"examined mutants and found survivors" is true of such a run and must not be read as licence to write.

For a run that reached here, the discriminator is whether it **examined** anything, not whether it
found anything:

- **Rows to emit** → write.
- **At least one mutant examined, no rows to emit** — no survivors, or every survivor was arid or
  equivalent → **write anyway**, with the `## Findings` header row and no data rows. The payload is
  `## Surfaces`. A surface that ran and returned nothing is coverage information, and the consumer
  unions `## Surfaces` across producers precisely so that information is not lost; a merged report
  saying only "the reviewers found three things" reads differently from one that also says the
  mutation surface ran over these files and found nothing, and the second is the true one. An empty
  table still meets the admission test, so the file is consumed and its coverage reaches the plan.
- **No mutant examined** — an empty scope, everything dropped by coverage or suppression, a cap that
  dropped the whole set, or a Phase 0 refusal → **write nothing.** There is no coverage to report,
  and a `## Surfaces` line claiming this surface ran would assert coverage never attempted, which the
  contract's omit-rather-than-fabricate rule forbids. Say so in the Phase 5 report instead.

A partial run writes what it found and names what did not run, exactly as the partial-run rule in
Gotchas governs the report — "partial" there meaning mutants that never ran, never a run whose tree
was left mutated.

## Coverage the file does carry, and what it omits

`## Surfaces` names this producer once and carries what it actually covered: the diff target, the
files mutated, mutants generated, survivors, suppressed, and anything a cap dropped. Whatever did not
run goes in that section's returned-no-result limb with its cause. Keep the section's stated line
form; only the values are this producer's to choose.

Omit `tier:` — a mutation run has no lifecycle-tier analogue, and the consumer renders an absent one
as unstated rather than guessing. Omit `## By dimension` — there is one dimension. Omit
`## Unparsed` — nothing goes unparsed here: every survivor is a structured record from Phase 3, and a
survivor whose equivalence claim lacked evidence is a row, not raw text.

## Re-running

A re-run writes what it currently finds and **never replays** — the contract's re-emission rule.
Concretely for this producer: never re-emit a previous run's file, never copy rows forward from one,
and never read the consumer's ledger to decide what to write.

## The tree after a persist run

Tracked source is byte-identical to the Phase 0 snapshot on three limbs, none of them assumed:
Phase 3 verified every revert against that snapshot, nothing in this phase edits tracked source, and
**both** of this phase's writes — the findings file and the guard's `.gitignore` — were proven outside
tracked space before either was made. The first limb is why this phase can describe a tree at all — a
run whose revert did not verify ends in failure at Phase 3 and never reaches here, so a findings file
never claims `Location`s against source left mutated. The third is
not traded for a findings file either: a destination that cannot be proven outside tracked space is
reported and not written to.
