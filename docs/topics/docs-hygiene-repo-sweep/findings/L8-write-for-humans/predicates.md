# Predicates

`docs-hygiene:write-for-humans` is authoring-time doctrine with no scan mode. This file turns it
into testable predicates so an audit can be run and, more importantly, so a reader can tell which
findings are decidable from the text and which are judgment.

Read `standard-resolution.md` first. Every predicate below is either sourced from the resolved repo
guide, or reached from a bundled layer only because the resolved guide is silent there. A predicate
the repo overruled is not listed; it is listed in `standard-resolution.md` as an override.

## How to read a predicate

| Field | Meaning |
|---|---|
| Source | The passage the predicate is traced to |
| Decidable | `mechanical` (a script can rule), `mechanical + adjudicated` (a script proposes, a reader rules), `judgment` (a reader rules) |
| Owner | This lane, or the sibling lane the finding routes to |

## Mode predicates

The resolved guide has no document-mode layer, so these come from the skill's Diátaxis section.

### `M1` One document, one mode

A document serves doing or understanding, and learning or work. It picks one cell and links to the
others.

- **Source**: skill body, "Pick the mode first" and "**Do not mix modes.** No reference tables inside
  a tutorial, no hand-holding inside reference, no arguing inside a how-to. Split and link instead."
- **Decidable**: judgment
- **Owner**: this lane
- **Test**: name the mode the document's title and lead promise. Then read each `##` section and name
  its mode. A section whose mode differs from the document's, and that is not linked out, fails.
- **Note**: the skill's fourth gotcha says the compass applies to the paragraph, not only the whole
  document. A README carrying one explanation section is still a mixed document.

### `M2` Release history belongs in the changelog

A reference document states what is true now. Version deltas, regression narratives, and "this used
to be X" belong in the sibling `CHANGELOG.md`.

- **Source**: two places agreeing. Skill body, "**Reference. Facts for lookup.** Describe, and only
  describe." And this repo's own split, enforced by `scripts/check-changelog-parity.sh`, which
  requires every versioned plugin to ship a `CHANGELOG.md` that carries the version history.
- **Decidable**: mechanical + adjudicated. Grep for `since <x.y.z>`, `the <x.y.z> delta`,
  `pre-<x.y.z>`, `no longer`, `previously`, `formerly`, `used to`. Then rule on each hit.
- **Owner**: this lane, overlapping `L5-noise`'s historical-citation shape. The distinction: `L5`
  asks whether the citation points at superseded state; `M2` asks whether a *current* reader of a
  reference document gains anything from the sentence at all.
- **Exemption**: a delta a current reader needs to explain present behavior stays. "Default off since
  0.20.0" tells a user why a hook they expected is silent. "Exec form is the regression this plugin
  hit twice" does not.

### `M3` One place per recurring block

A block that appears in many documents of one class appears under the same heading in all of them.

- **Source**: skill body's third survives-the-guide rule ("The thing being documented supplies the
  vocabulary") plus the ambiguity layer's "Call each thing by one name, everywhere. A document that
  says 'the gate', 'the ratchet', and 'the budget check' for one thing teaches three things."
- **Decidable**: mechanical
- **Owner**: this lane
- **Test**: for each recurring block, record the `##` heading it sits under across the class. A
  minority placement fails.

## Address predicates

Reached from the Google layer only where the resolved guide is silent. The resolved guide's own
"Active voice, named actor" rule covers most of this layer already and routes to `ai-slop:audit`.

### `A1` An instruction is a command, with its condition first

- **Source**: `reference/sentence-rules.md`, "Write instructions as commands", "Put the condition
  before the instruction".
- **Decidable**: mechanical + adjudicated
- **Owner**: this lane
- **Calibration, and why this predicate filed nothing**: the mechanical proxy (`should be <verb>ed`,
  `must be <verb>ed`) returned 47 hits across the human slice and **all 47 adjudicated as
  non-instructions**. They are constraint statements in explanation and reference register, where the
  actor genuinely does not matter ("a tracked file must be proven safe"). This is the same shape
  `docs/specs/d1-model-already-knows-measurement.md` measured and ruled on: a cue that correlates
  with the class it is meant to detect only weakly, over a corpus whose house style writes its
  load-bearing rules as bare imperatives. The predicate is sound; the proxy is not, and this lane
  files no `A1` findings rather than guessing.

### `A2` No "simply", "easily", "quickly", or "obviously" in a procedure

- **Source**: `reference/sentence-rules.md`, "never 'simply', 'easy', or 'quickly' in a procedure. If
  it were simple the reader would not be here."
- **Decidable**: mechanical + adjudicated
- **Owner**: this lane
- **Calibration**: 33 hits across the human slice. All 33 are the *"merely"* sense in explanation
  prose ("a corpus may simply lack a case", "it would simply be absent"), not the *"this is easy"*
  sense in a procedure. The rule is scoped to procedures and none of these are in one. **Zero
  findings.**

## Load predicates

### `L1` One thought per sentence, and no backtracking

- **Source**: the resolved guide, "Plain speech": *"**One idea per sentence.** If the reader must
  backtrack to parse it, break it in two or drop clauses."* The bundled ASD-STE100 layer's numeric
  thresholds (20 words for an instruction, 25 otherwise) are used only as a first filter, because the
  resolved guide states the rule as a parse test, not a word count, and its own "Vary rhythm" entry
  explicitly protects the long sentence that carries one thought.
- **Decidable**: mechanical + adjudicated. Filter: a sentence of 45 or more words carrying 3 or more
  clause interrupters (a parenthetical of 12 or more characters, a semicolon, a mid-sentence colon,
  or a comma followed by `which`/`where`/`so that`/`because`). Then rule on each.
- **Owner**: this lane, overlapping `L6-compress`, which trims words inside a sentence but does not
  split one. A `L1` finding is a split, not a trim.
- **Why both conditions**: length alone fails the resolved guide, which asks for rhythm variety.
  Length plus stacked interrupters is the parse test made checkable.

## Ambiguity predicates

The resolved guide has no ambiguity layer, so this whole group is reached from Global English. It is
where this lane's highest-confidence findings sit.

### `Am1` A parenthetical is a full grammatical unit

- **Source**: `reference/sentence-rules.md`, "Make text in parentheses a full grammatical unit or its
  own sentence."
- **Decidable**: mechanical + adjudicated. Find a parenthetical containing an internal sentence
  boundary (`. ` followed by a capital), then rule on whether the span before that boundary is a
  complete clause.
- **Owner**: this lane, exclusively. `ai-slop:audit` cannot see it: the em dash it was told to remove
  is already gone.
- **Why this class exists**: the repo-wide de-slop at `36356429` applied the resolved guide's
  substitution guardrail ("If the thought needs separation, end the sentence") *inside* parentheses.
  Ending a sentence inside a parenthetical leaves a fragment on one side of the period. This is the
  guardrail working exactly as written and producing text that does not parse, which is precisely
  the case the resolved guide's own preamble reserves judgment for.
- **Pass**: a parenthetical holding two complete sentences, capitalised and punctuated as such, is
  correct. `plugins/adhd/README.md:105` is the model: `(There is no runtime coupling between the
  plugins to enforce this. It is a usage guideline.)`

### `Am2` No `(s)` plurals in prose

- **Source**: `reference/sentence-rules.md`, "Never form plurals with '(s)'."
- **Decidable**: mechanical
- **Owner**: this lane
- **Scope**: prose only. A table column header is a label, not a sentence, and the repo uses
  `Tier(s)` / `File(s)` / `Lane(s)` as compact headers. Header hits are not findings.

### `Am3` No slash coordination in prose

- **Source**: `reference/sentence-rules.md`, "No slashes: write 'a, b, or both' instead of 'a/b' or
  'and/or'."
- **Decidable**: mechanical
- **Owner**: this lane
- **Scope**: prose only, and only where the slash is coordinating. A term of art
  (`either/or marker logic`), a path, a command, and a vendor pair (`Windows/Git Bash`) are not
  coordination.

### `Am4` "only" sits next to the word it changes

- **Source**: `reference/sentence-rules.md`, "Keep words like 'only' and 'not' next to the word they
  change."
- **Decidable**: judgment
- **Owner**: this lane
- **Calibration**: the corpus uses `only` about 900 times in the human slice. A mechanical proxy over
  that population would be the D1 failure again, so this predicate was applied by reading, not by
  scanning, and only within documents already opened for another predicate. See the recall statement
  in `README.md`.

## Naming and claim predicates

### `N1` One name per thing

- **Source**: two agreeing. The skill's survives-the-guide rule 3, and the resolved guide's "In
  technical prose, specificity bows to terminology consistency: one name per concept, reused
  exactly."
- **Decidable**: judgment
- **Owner**: this lane, overlapping `L3-ssot` where the second name is in a second file.

### `C1` The real name and the real number

- **Source**: skill's survives-the-guide rule 3: *"Counts, file trees, and inventories are claims
  too: each must be true at the commit that lands it, and the doc should carry the command that
  regenerates it."*
- **Decidable**: mechanical
- **Owner**: **already owned by CI.** `scripts/check-skill-count-claims.sh` checks every prose claim
  about how many skills a plugin bundles against the tree, and fails the build on a mismatch. Its own
  header records why: *"A reviewer catch is not a control. It is a coin flip that happened to land
  right."*
- **Result**: this lane re-ran the check independently across all 71 plugin READMEs, comparing every
  `<number> skills|hooks|agents|plugins` claim against the actual tree. **Zero live violations.** The
  predicate holds and the gate is doing its job. Nothing to file.

## Predicates delegated, not applied

| Predicate | Source | Routed to |
|---|---|---|
| Cut every word that does no work | Skill rule 1; guide "Filler" | `ai-slop:audit`, then `L6-compress` |
| Use the short, everyday word | Skill rule 2; guide "Prefer the plain word", "Metaphor jargon" | `ai-slop:audit` |
| No em dash, no substituted en dash or spaced hyphen | Guide "Substitution guardrails" | `ai-slop:audit` |
| Stacked hedging, chat residue, promotional tone | Guide "Replacements for flagged phrases" | `ai-slop:audit` |
| Historical citation, ghost ref, plan reference | Not in either standard; repo skill | `L5-noise` |
| Commit subject and PR body shape | Skill "What this skill does NOT do" | `source-control` |
