# Persisting survivors — this plugin's read of the detector-findings contract

## Contents

- [Where the file goes](#where-the-file-goes)
- [Prove the destination is outside tracked space before writing to it](#prove-the-destination-is-outside-tracked-space-before-writing-to-it)
- [What each cell says](#what-each-cell-says)
- [Tier and Confidence come from the rule, and the rule from the verdict class](#tier-and-confidence-come-from-the-rule-and-the-rule-from-the-verdict-class)
- [When the file is written at all](#when-the-file-is-written-at-all)
- [Coverage the file does carry, and what it omits](#coverage-the-file-does-carry-and-what-it-omits)
- [Re-running](#re-running)
- [The tree after a persist run](#the-tree-after-a-persist-run)

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
`.gitignore` — and its second invalid case, named in "Prove the destination is outside tracked
space", where no checkout can be shown to govern a resolved root and this phase writes nothing there
at all.

File name: `${TS}-mutation-survivors.md`, with `TS="$(date -u +%Y%m%dT%H%M%SZ)"` — colon-free and
Windows-safe, so lexical sort equals chronological sort.

**Never overwrite an existing path.** When `${TS}-mutation-survivors.md` already exists, write
`${TS}-mutation-survivors-2.md`, then `-3`, taking the smallest free integer ≥ 2. Two runs inside the
same second is the ordinary cause, and overwriting would destroy a file this producer had already
handed to the merge set — the same defect as writing into a file another producer owns.

## Prove the destination is outside tracked space before writing to it

This phase makes **at most two** writes — the findings file and, when the self-ignore guard heals a
root, that root's `.gitignore` — and the property to prove is that git picks up neither. **Each is
proven before that write is made**, which is the strongest form available and not the same as proving
both up front: on a fresh root the guard's file is exactly what makes the findings file's probe pass,
so that probe cannot precede the guard. "At most" is load-bearing — where no governing checkout is
found, neither write happens at a resolved root (step 1).

**The one write that survives that branch is proven by step 1 itself, not by a probe.** The
`${CLAUDE_PLUGIN_DATA}` fallback is written there, and what proves it safe is the agreement of two
independent signals that no checkout governs the path: a destination outside every checkout cannot be
tracked by one, so there is no ignore rule to satisfy and nothing for `check-ignore` to answer. That
is a proof, not an exemption — which is why step 1 needs both signals and why a single-signal version
of it would be fail-open rather than merely weaker. The order below is what makes the per-write form
hold everywhere else:

0. **Make the resolved root a physical path first.** `cd` to its nearest existing ancestor, take
   `pwd -P`, and re-append the components below it. A lexical walk over a path whose ancestor is a
   symlink into a checkout never visits the physical parents inside that checkout, finds no `.git`,
   and takes step 1's permissive branch while git in that checkout sees the files perfectly well.
   `pwd -P` is POSIX and needs no `realpath`.
1. **Find every governing checkout, from two signals that must both come back empty** before the
   permissive branch is taken:
   - **The walk.** `test -e <ancestor>/.git` up the physical path, `-e` and not `-d` because a
     worktree's `.git` is a file. The first ancestor with one is a governing checkout `T`.
   - **`rev-parse`.** `git -C <the nearest existing physical ancestor> rev-parse --show-toplevel`,
     run under the **ambient** environment. A toplevel it reports is a governing checkout even when
     the walk found none.

   **No checkout governs the path only when both come back empty** — and that is the branch on which
   this producer writes **nothing**, not the branch on which it writes freely. Either signal alone is
   fail-open in a state the other sees: the walk cannot see a working
   tree designated by `GIT_WORK_TREE`/`GIT_DIR`, where nothing in the path has a `.git` at all yet git
   reports tracked files there; `rev-parse` cannot tell "no repository" from a missing directory, a
   dangling `gitdir:`, or a discovery limit, all of which are exit 128. They do not fail on the same
   inputs, so requiring agreement narrows the permissive branch to what neither can see alone. Where
   both report one and they differ, prove against **both** — steps 3 and 5 run per checkout and every
   one must pass.

   **One topology defeats both signals, and the permissive branch is shaped around it.** A repository
   whose `core.worktree` points at the destination's tree — including the bare-layout variant with
   `core.bare false` — governs that tree with **no `.git` anywhere in the destination's path and
   nothing in the environment to find**. The designation lives in a config file that destination-side
   discovery never reaches, so both signals come back empty together.

   **On the permissive branch this producer writes nothing at all — with one exception, below.** Not
   the guard's `.gitignore`, and not the findings file. The guard's half is the
   [topic-docs convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md) "Runtime guards"
   second invalid case, which owns the rule and why; nothing is re-derived here. The findings file
   follows for the same undecidability applied to this skill's own contract: the destination may be
   an **index-tracked deletion** in the checkout the detection missed, and writing it there produces
   a *modified tracked file* rather than a new untracked one — measured. "Read-only with respect to
   tracked source" admits no such write, so the branch that cannot rule it out cannot take it.

   Report the resolved destination, say that no checkout could be shown to govern it and the findings
   were therefore not persisted, and stop. A refusal a human can act on is the correct end of this
   branch; it is not a silent skip.

   **The exception is the contract's `${CLAUDE_PLUGIN_DATA}` fallback**, which the rung order takes
   when there is no project root at all. That surface is outside every checkout **by construction**,
   so no tracked deletion can hide there and the refusal has nothing to protect — write, and announce
   the absolute path as the contract requires. Refusing it would strand the one destination a
   headless run on a rootless directory is *supposed* to use.

   Two cases the signals resolve rather than defer: a **bare** repository with no worktree puts no
   `.git` in any ancestor and reports none, so it reaches this branch and the run refuses. That
   refusal is conservative rather than necessary — a repository with no working tree picks nothing
   up — but the signals cannot distinguish it from the `core.worktree` topology, which is the whole
   reason the branch refuses; a rule that guessed which one it was facing would be the fail-open this
   step exists to prevent. (A bare *layout* that names a worktree through `core.worktree` is that
   topology, not this one.) A destination **inside a checkout's own `.git/`** is refused
   here, by name: `check-ignore` answers exit 1 for it, which step 5 would report as "tracked space",
   and `.git/` is not that.
2. **Reject a root-equivalent `memory_dir`** — the contract's invalid-root rule, judged against `T`
   rather than the invoking worktree, since a root that is *another* checkout's toplevel would heal
   into *that* repo's root `.gitignore`.
3. **Prove the guard's write before the guard makes it:** `git -C T ls-files -- <the resolved root>`.
   **Exit 0 with empty output** proceeds; **exit 0 with any output** means the root holds tracked
   files — a source directory, where healing `*` rewrites the ignore semantics of files the consumer
   owns — and refuses; **any other exit** means the probe did not evaluate the path and also refuses,
   reporting the status. Reading "no output" alone as a pass is the trap: a fatal `ls-files` prints
   **nothing** to stdout and exits 128, so exit status and output must both be read or a failure
   passes for a clean root. Stop here, before anything is created — this step, not a later report, is
   what keeps the guard's write inside the proof.

   `ls-files` reads the **index**, so it proves "no tracked files" and not "no files the consumer
   owns": a source directory whose files were never added is invisible to it, and healing `*` there
   makes a later `git add` skip them silently. Narrow that residual by also refusing when the root
   already exists and holds an entry that is neither `.gitignore`, nor a `*.md` file, nor a
   directory, nor an OS-generated artifact — `desktop.ini`, `Thumbs.db`, `.DS_Store`. **Not "only
   files this producer wrote"** — the contract has producers share one directory, so other producers'
   findings files and the consumer's own records are the ordinary steady state and must not trip
   this, and the OS entries would otherwise refuse a perfectly good memory root on Windows or macOS
   for a file no human put there. What the rule excludes is a root that looks like source: a `.py`, a
   `.cs`, a `Makefile`. It is a heuristic and is stated as one; it narrows the residual rather than
   closing it.
   The precondition itself is the self-ignore guard's, not this producer's — the
   [topic-docs convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md) "Runtime guards"
   owns where that guard may heal; what is stated here is only how this producer discharges it before
   its own writes.
4. **Create the memory root**, **run the self-ignore guard**, then create the destination directory.
5. **Prove the findings file:** `git -C T check-ignore -q -- <the exact intended file path>`, and
   **write only on exit 0.**

**Why step 1 needs the walk as well as `rev-parse`, and trusts neither alone.** `rev-parse` fails
identically — exit 128 — for "there is no repository", for "that directory does not exist", and for a
discovery limit such as `GIT_CEILING_DIRECTORIES` under which a repository *does* govern the path.
Reading any non-zero as "no repository" would be fail-open at the one step that decides whether the
rest of the proof is needed — which is why `rev-parse` is a *concurring* signal here and never a
deciding one. The walk supplies what it cannot: no ambiguous state, no need for the directory to
exist yet (so steps 2 and 3 run before anything is created), and nothing in the environment narrows
it. Neither is trusted alone. It is also not a path-prefix comparison: comparing two paths as strings
needs **both** canonicalized, and `realpath` and `readlink`'s canonicalizing flag are GNU-only —
where step 0 needs one physical starting point, which `pwd -P` gives portably.

**Anchor steps 3 and 5 to a governing checkout, never to the invoking worktree.** A `memory_dir`
resolving outside the worktree is a supported configuration the consumer handles explicitly
(`fix-pass-mode.md` "Step 1", the shared-findings-directory bullet), and `git check-ignore` on a path
outside its repository is `fatal: … is outside repository`, exit 128 — so a worktree-anchored probe
can never succeed there, and `--persist-findings` would refuse every write in precisely the layout the
consumer supports. Anchoring to the checkout that governs also answers the case the invoking worktree
cannot see at all: an external root that sits inside *another* checkout, whose tracked space is just
as real.

**`git -C` is not by itself an anchor.** `GIT_DIR` and `GIT_WORK_TREE` override it: with either set,
`git -C T` answers about a different repository entirely. Run each checkout's probes under the
environment that actually addresses it — the ambient one for a checkout `rev-parse` found *through*
those variables, and with them cleared for a checkout the walk found on disk. Do not simply strip
them: an environment-designated working tree is a real tree that really picks writes up, which is the
whole reason step 1 asks `rev-parse` under the ambient environment rather than a scrubbed one.

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
- **`Finding`** leads with the rule id and what fired it, then states the mutation and the outcome:
  the operator, the before → after fragment, and that the covering tests still passed. Neither
  `Finding` nor `Action` carries the Phase 4 reviewer's reasoning — the row is the artifact, not the
  argument for it.
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

### The remediation site is not the finding site, and that is declared

`Location` is the mutated node, while the missing assertion belongs in the test that covered it — a
different file. Every rule this producer emits under is therefore **off-site**, which the contract's
crosswalk declares in its auto-applicable cell and the consumer reads as its instruction to surface
the row rather than apply it. Naming the target in `Action` is the producer half of that contract,
not a workaround.

**Do not engineer around it:** never retarget `Location` at the test file to make a fence fit — it
would destroy the row's identity and its cross-producer collapse key — and never invent a column the
shape does not define. A surfaced mutation row reaching a human is the intended end of the route.

## Tier and Confidence come from the rule, and the rule from the verdict class

Phase 4 assigns every survivor exactly one class, and the class alone selects the rule. Nothing in
the finding's prose does. **The rule then decides the tier, the disposition, and the
auto-applicability — all of them in the contract's crosswalk, which is where the argument for each
lives.** This table is the whole selection map, and it is the one part a mutation run owns:

| Phase 4 class | Rule id |
|---|---|
| **Productive** | `mutation-testing/audit/rule-survivor-productive` |
| **Unclassified** | `mutation-testing/audit/rule-survivor-unclassified` |
| **Arid** | `mutation-testing/audit/rule-survivor-arid` |
| **Equivalent** | `mutation-testing/audit/rule-survivor-equivalent` |

**The class alone is the key because the evidence bar is already in it.** Both withholding classes
reach this phase having met their demonstration requirement, because SKILL.md "Phase 4" applies that
requirement at classification and reports a claim that cannot meet it as *unclassified* — so no
survivor arrives here labelled arid or equivalent without its evidence. That placement is deliberate
and load-bearing for the contract's fail-safe criterion: Phase 5 reports and Phase 6 persists from
one classification, so a survivor has **one** disposition rather than one in the report and another
in the findings file, and the bar binds a bare run too, which is where an unevidenced withholding
claim is read by a human.

**Write the id in full.** The contract defines one form and no short one, because the crosswalk is a
cross-producer registry and an emitted id is resolved against a row by exact match. This is **not**
the `check:` value a suppression uses — that keys to the mutation operator (see "Remediation —
delegated"), deliberately finer, because a suppression retires per mutant while a rule classifies a
disposition.

**Every emitted row leads its `Finding` cell with the rule id and the threshold that fired** — for
this producer the threshold is the mutant's executed state and the class Phase 4 assigned, in the
run's own values (the operator, the surviving state, the covering tests that passed). Reading the row
against its crosswalk entry is then the whole severity audit, with no return trip to this skill.

Two consequences the crosswalk states that a run must actually carry out:

- **A DEMONSTRATED arid or equivalent verdict emits no row** — and only a demonstrated one. Arid's
  only remediation is a suppression entry this skill proposes and never writes unprompted, accepted
  by the user per "Remediation — delegated"; Phase 5 still shows every arid survivor and its proposed
  entry to the human, so nothing is lost. Equivalent is not a defect. Those two are reported as
  declined-candidate counts, below; an undemonstrated one is not declined at all and emits under the
  rule the next bullet names.
- **An unevidenced withholding claim never reaches this phase as a withholding class.** Phase 4 owns
  that bar for both classes and reports a claim it cannot meet as *unclassified*, which maps to
  `mutation-testing/audit/rule-survivor-unclassified` and emits at IMPORTANT. Do not re-apply the bar
  here and do not soften it: reaching for a withholding label is the standard way this technique
  manufactures false confidence (see Gotchas), and the requirement is what stops the claim from
  burying the finding.

Where the consuming project defines its own severity vocabulary, the contract's precedence rule binds
this producer too: map to the project's tiers, with the crosswalk's value as the fallback.

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

**Declined candidates go in the returned-no-result limb as counts per rule id** — `2 declined
(mutation-testing/audit/rule-survivor-equivalent), 1 declined
(mutation-testing/audit/rule-survivor-arid)` — never as per-mutant rationales. The
contract's "A candidate that is not a finding" owns why: a count is what a trend across runs can be
read from, and a section carrying one line per surface stops being that the moment it carries an
argument per mutant. **Only a demonstrated verdict is counted here** — an undemonstrated arid or
equivalence claim is a row, not a decline, so counting it would report a candidate as declined while
it sits in the findings table. The rationale for each withholding judgment, of either kind, goes in
the Phase 5 report to the human, which is where an argument belongs; the file carries the artifact.

Omit `tier:` — a mutation run has no lifecycle-tier analogue, and the consumer renders an absent one
as unstated rather than guessing. Omit `## By dimension` — there is one dimension. Omit
`## Unparsed` — nothing goes unparsed here: every survivor is a structured record from Phase 3, and a
survivor whose withholding claim lacked its evidence, arid or equivalent, is a row rather than raw
text.

## Re-running

A re-run writes what it currently finds and **never replays** — the contract's re-emission rule.
Concretely for this producer: never re-emit a previous run's file, never copy rows forward from one,
and never read the consumer's ledger to decide what to write.

## The tree after a persist run

Tracked source is byte-identical to the Phase 0 snapshot on three limbs, none of them assumed:
Phase 3 verified restoration against that snapshot, nothing in this phase edits tracked source, and
each of this phase's two writes — the findings file and the guard's `.gitignore` — was proven outside
tracked space before that write was made. The first limb is why this phase can describe a tree at all — a
run whose restoration did not verify ends in failure at Phase 3 and never reaches here, so a findings file
never claims `Location`s against source left mutated. The third is
not traded for a findings file either: a destination that cannot be proven outside tracked space is
reported and not written to.
