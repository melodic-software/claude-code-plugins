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

## Prove the destination is ignored before writing to it

Run `git check-ignore -q -- <the exact intended file path>` and **write only if it reports the path
ignored.** Otherwise report the resolved path, say the findings were not persisted because that path
is tracked space, and stop.

This is a positive check, and the distinction matters because the obvious alternative is worthless: a
`.gitignore` whose content is `*` matches **itself**, so a resolved root inside tracked space leaves
`git status --porcelain` byte-identical to the Phase 0 snapshot whether the write was ignored or not.
Comparing porcelain before and after therefore cannot detect the failure it appears to test.

Three states this catches that reasoning about the guard alone does not:

- A `memory_dir` or `CLAUDE.md`-declared location resolving **inside a tracked tree**. The
  invalid-root rule rejects a root-*equivalent* value, not every tracked one, so this resolves
  legally and still lands in tracked space.
- A resolved root whose `.gitignore` **exists but does not ignore the file** — the guard creates one
  only when absent, so a present-but-narrower file is a state no creation step reaches.
- Any consumer-side ignore rule that **re-includes** the path (a later negation pattern), which no
  amount of writing `*` at the root of the memory tier overrides.

The guard may itself create a `.gitignore`; that write is the guard's, is announced, and is the only
write this phase makes outside the findings file. Both are subject to this check.

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

The discriminator is whether the run **examined** anything, not whether it found anything:

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
Gotchas governs the report.

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

Tracked source is byte-identical to the Phase 0 snapshot, because nothing in this phase edits tracked
source and the destination was proven ignored before the write. That property is not traded for a
findings file: when the destination cannot be proven ignored, the run reports why and persists
nothing.
