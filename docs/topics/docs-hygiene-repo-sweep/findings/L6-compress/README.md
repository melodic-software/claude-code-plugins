# L6-compress — roll-up

Lane: `/docs-hygiene:compress`, `audit` action only. Read-only. No source file was edited.

## Why audit-only

The skill's default action requires a semantic-diff subagent as a mandatory gate, and it is
explicit that the compressing context must not be the verifying context. This lane's context cannot
spawn subagents, so the default action is structurally unavailable here and self-review is not a
substitute. Everything below is a remediation spec for wave 3, gated in wave 4 from a context that
can spawn the verifier.

## Counts

| Class | Mechanical scan | After adjudication |
|---|---|---|
| SKIP | 1280 | 1267 |
| COMPRESS | 10 | 35 |
| UNCERTAIN | 12 | 0 |

Full table in `classification.md`; raw per-file scan output in `scan-raw.md`.

The two columns share no COMPRESS members. Every mechanically-nominated file was overturned, and
every proposed file was promoted from a mechanical SKIP. That is not the scan misfiring so much as
the scan doing what it is scoped to do: its signal-6 token list is single-word and deliberately
narrow, and it cannot see quotation boundaries. Both limits are recorded under
"Recheck-trigger evidence" below.

## The two findings

**C1, 34 plugin READMEs.** One verbose form, `in order to` to `to`, in the generated plugin-options
block. Per-file spans in the eight per-group files.

**C2, one file.** One stacked-hedge intensifier in
`plugins/overengineering/skills/delta/context/recurring-wiring.md:83`. Spec in `G-code-design.md`.
This is the only proposed cut in the sweep that is a plain markdown edit.

## Finding C1 remediation

**Do not hand-edit the 34 READMEs.** Every span sits between
`<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->`
and `<!-- END GENERATED: plugin options -->`. Verified for all 34: each hit line's number falls
strictly between its file's two marker lines. The generator's docstring states CI runs `--check` and
rejects drift, so a hand edit fails CI and is overwritten on the next sync.

Three steps. The fenced blocks below sit at column zero on purpose, so their contents are
byte-exact against the generator source, leading whitespace included. Do not read them as
list-indented.

### Step 1 — `scripts/sync-plugin-options-docs.py:100`

The string literal for the 32 files that declare at least one non-sensitive option.

Before:

```text
            "   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to",
```

After:

```text
            "   `project`/`local` scope. Do **not** `claude plugin uninstall` to",
```

### Step 2 — `scripts/sync-plugin-options-docs.py:128`

The string literal for the sensitive-only branch, which produces the two variant-B files
(`dometrain`, `miro`).

Before:

```text
            "   `claude plugin uninstall` in order to reconfigure either: uninstalling drops this",
```

After:

```text
            "   `claude plugin uninstall` to reconfigure either: uninstalling drops this",
```

### Step 3 — regenerate

Run `scripts/sync-plugin-options-docs.py` with no arguments to rewrite every plugin README, then
`scripts/sync-plugin-options-docs.py --check` to confirm it reports clean.

**This crosses out of the markdown corpus.** `scripts/sync-plugin-options-docs.py` is not in
`inventory/manifest.tsv` and is not any lane's assigned surface. The orchestrator owns the decision
to touch it. If the answer is no, C1 is dropped entirely rather than applied to the markdown: a
partial application is strictly worse than none, because it fails CI and reverts.

**Cross-lane hazard, wider than this lane.** The same generated block is present in 34 plugin
READMEs and spans roughly 70 lines each. Any lane whose remediation edits inside those markers
(L5 noise removal, L7 and L8 conformance rewrites are all plausible) hits the same CI rejection.
Worth a single check during wave 2 reconciliation: reject any per-file edit whose line number falls
inside a `BEGIN GENERATED` / `END GENERATED` pair, and route it to the generator instead.

## Projected yield by tier

| Tier | Files in corpus | Files proposed | Projected yield |
|---|---|---|---|
| T1 | 3 | 0 | 0% |
| T2 | 250 | 0 | 0% |
| T3 | 1049 | 35 | 0.062% across the 35 proposed files; 0.0018% corpus-wide |

**Method.** Byte-exact, not estimated. C1 removes 9 bytes (`in order`) from each of 34 files whose
combined size is 499,481 bytes: 306 bytes, or 0.061% of those files. C2 removes 6 bytes (`quite`)
from a 7,420-byte file, 0.081% of it. Total 312 bytes; the 35 proposed files total 506,901 bytes,
and the corpus totals 17,422,358 bytes. Denominators are the `bytes` column of
`inventory/manifest.tsv`, summed; numerators are the byte lengths of the removed spans.

**Nothing is proposed in T1 or T2.** All three T1 files fall under signal 1. Every T2 file is a
`SKILL.md` and also falls under signal 1, which the skill body bounds empirically at 2 to 3% with a
3-out-of-3 revert record. Given that this repo's markdown was de-slopped repo-wide two commits
before this sweep (`36356429`), the realistic T2 yield is lower still, and the whole tier's
projected value is below the cost of the semantic-diff dispatch it would require. This lane declines
it rather than reporting a number it cannot stand behind.

**The yield number is not the argument for C1.** 312 bytes is far below any threshold that would
justify a compression pass on its own, and the skill's own default rule would revert a diff this
small without `--force`. What justifies C1 is that it is a conformance fix, not a size fix: this
repo states its own rule at `plugins/docs-hygiene/skills/write-for-humans/SKILL.md:56`
(`"In order to" is "to".`), applied it repo-wide in the `/ai-slop:audit fix` pass recorded in
several CHANGELOGs, and this block escaped that pass because it is generated rather than authored.
34 copies of a rule violation in the most-read surface in the repo is worth one generator line. If
the orchestrator weighs it purely on bytes, declining is the defensible call.

## What I judged UNCERTAIN and why

Nothing was left UNCERTAIN. The mechanical scan emitted 12 UNCERTAIN rows and all 12 resolved on
reading, each on a fact the scan cannot see rather than on a judgment I could not make. The
per-row reasons are in `classification.md`, "Mechanical UNCERTAIN, resolved to SKIP".

Two calls were close enough to name here.

**`plugins/architecture/skills/improve/actions/deepening.md:56`** and
**`plugins/event-storming/skills/methodology/reference/big-picture-workshop.md:224`** both carry
`in terms of`, which is on the verbose-form list. Both were held SKIP because the shorter form needs
the surrounding clause re-punctuated. That is a rewrite, not a word drop, which puts it outside this
lane's word-level latitude and inside `write-for-humans`. Flagged here so L8 can pick them up if it
wants them.

**`plugins/claude-config/skills/audit-pass/reference/terms.md`** sits exactly on the
5-per-kilo-word threshold on a single token in a 188-word file. It resolved to SKIP on the token
being a scope qualifier, but a file this small makes the density signal meaningless in either
direction, and I would not defend the scan's verdict on it.

## Recall limits

Five, stated plainly.

1. **Article drops are not proposed, anywhere.** The batch fan-out latitude includes dropping
   `the` / `a` / `an` before clear nouns, and across 1302 files that is certainly the largest
   nominal source of removable bytes in the corpus. It is excluded deliberately. Producing it as a
   spec means quoting thousands of before and after pairs, each individually below the threshold at
   which a semantic-diff gate can say anything useful, against an empirical record of 9 out of 9
   such files reverting at 0.02 to 0.4%. If the orchestrator wants article drops, the honest route
   is the skill's own default action on named files with the gate attached, not a spec from this
   lane.

2. **Passive-to-active and nominalization conversions are not proposed.** Both are on the batch
   latitude list. Neither can be detected mechanically with acceptable precision, and neither
   produces a span a semantic-diff gate can adjudicate as pure flavor: converting a passive changes
   which noun is the sentence's subject, which is a content-adjacent edit. This lane's output is
   scoped to what the gate can actually rule on.

3. **The verbose-form sweep is a fixed list, not a model pass.** Stage 2 searched 15 named
   multiword forms plus the stacked-hedge and redundant-pair lists. A verbose construction outside
   that list, and outside `audit-scan.sh`'s single-word list, was not looked for. Recall on
   "all flavor" is therefore well under 100%; recall on "the forms the matrix and the ai-slop
   catalog name" is complete.

4. **Quoted-text detection was line-based.** Stage 2 classified a token as quoted if its line began
   with `>` or the token sat inside double quotes on the line. A flavor token in unquoted prose
   immediately adjacent to a long quotation could have been misread as quoted and skipped. This
   biases toward SKIP, which is the safe direction for a lane whose errors are otherwise
   irreversible content loss.

5. **`plugins/*/skills/*/vendor/**` was not read.** Out of scope per
   `.claude/rules/vendor-docs-are-not-style.md`. Those 22 files are the corpus's most likely
   third-party pasted prose, the matrix's highest-yield category at 10 to 20%. Whatever yield exists
   there is invisible to this lane by design.

## Recheck-trigger evidence

`plugins/docs-hygiene/skills/compress/context/target-types.md` "Recheck triggers" invites evidence
back. This run produced two items, recorded here rather than applied, since editing the skill is
outside this lane's boundaries.

**Confirmation of an existing trigger.** The row "Default-fallback files (signal 5) consistently
yield <5%" fired again. 8 of the 10 mechanical COMPRESS rows and 8 of the 12 UNCERTAIN rows
overturned on the reason that trigger already names: flavor tokens sitting inside protected quoted
text. The two songwriting research files and the Beck methodology file are the clearest cases, with
every single hit inside a verbatim quotation.

**A new shape the signals do not model: contrastive `actually` and `just`.** Both tokens are on
`audit-scan.sh`'s flavor list and both read as filler in isolation. In this corpus they overwhelmingly
mark a matrix (c) counter-example half ("not just one", "don't just spot-check") or a matrix (d)
claim-versus-reality qualifier ("does it resolve enablement the way Claude Code actually does").
This is predictable from the corpus's subject matter: a repo full of audit skills talks constantly
about the gap between what a doc claims and what the code does, and `actually` is the word for that
gap. A cheap mechanical refinement would be to discount a `just` preceded by `not` within three
tokens, and to discount `actually` on a line that also contains `claim`, `says`, `documented`, or a
`not` clause. Both are heuristics, and both would have to be measured before being trusted.

**A structural gap: generated blocks.** Neither the six signals nor the target-validation gates know
about generated regions. Gate 5 excludes `evals/fixtures/` because compressing deliberate test input
corrupts an eval; the same argument applies with more force to a CI-checked generated block, where
the edit does not merely corrupt something, it fails the build and is reverted. A gate 6 excluding
any span between `BEGIN GENERATED` and `END GENERATED` markers would have caught all 34 files in
this run mechanically, before any reading. That is the single highest-value change this run
suggests for the skill.

## Files in this directory

| File | Contents |
|---|---|
| `README.md` | This roll-up |
| `classification.md` | Adjudicated SKIP / COMPRESS / UNCERTAIN with per-row reasons |
| `scan-raw.md` | Raw `audit-scan.sh` output, 1302 rows, signal values inlined |
| `A-doc-quality.md` | 2 C1 spans |
| `B-cc-config-ops.md` | 5 C1 spans |
| `C-vcs-repo.md` | 4 C1 spans |
| `D-work-planning.md` | 2 C1 spans |
| `E-session-behavior.md` | 3 C1 spans |
| `F-quality-verify.md` | 1 C1 span |
| `G-code-design.md` | Finding C2 |
| `H-knowledge-research.md` | 6 C1 spans, both wrap variants |
| `J-toolchain-platform.md` | 11 C1 spans |

Groups `I-songwriting`, `K-repo-docs`, `L-docs-topics`, and `M-repo-root` have no COMPRESS files and
therefore no file here.
