# L5-noise: `negation`

**1229 candidates in. 7 findings out. 1222 rejected.**

All 7 findings are Tier 2, review needed. None is Tier 1. The reason is in "Why this lane does not
extrapolate" below: on this corpus a cue-based ruling on a bare imperative has a measured hostile
base rate, so every emitted row is one this lane read in its own file context, and no row is
emitted on form membership alone.

## Form taxonomy

Forms A through D were assigned mechanically over all 1229 candidates. Form E is the remainder,
adjudicated from a 60-row random sample.

| Form | Test | Population | Decision | Basis |
|---|---|---:|---|---|
| A: table-row attribution | cited line starts with `\|` | 30 | Reject, detector defect | full mechanical pass |
| B: blockquote | cited line starts with `>` | 28 | Reject, quoted material | full mechanical pass |
| C: quoted teaching corpus | path under `plugins/songwriting/context/pat-pattison/research/` | 114 | Reject | full mechanical pass plus source-header check |
| D: rubric exclusion clause | `Must NOT flag`, `never flag`, `not a finding` on the sentence | 26 | Reject | full mechanical pass |
| E: remainder | everything else | 1031 | Split, see below | 60-row random sample |

### Form A, table-row attribution, 30 candidates, rejected

The skill's own hard rule reads: "A table row still does not select: the cue must open the
sentence, and a row begins with `|`." Thirty candidates are attributed to a line that begins with
`|`. Examples: `plugins/claude-config/skills/audit/reference/audit-checklist.md:95`,
`plugins/claude-config/skills/audit-pass/reference/suppression.md:85`,
`plugins/claude-ops/README.md:34`.

This is the soft-wrap accumulation defeating the `|` guard: the accumulator joins physical lines
into a sentence before the classifier runs, so a row that wraps loses its leading pipe by the time
the opener test sees it. Reported as a detector defect, not as findings.

### Form B, blockquote, 28 candidates, rejected

The cited line opens with `>`. A blockquote is somebody else's words. Rewriting a quoted
prohibition into "the positive" falsifies the quote, which the repo's own style guide names as a
hard boundary (`plugins/ai-slop/skills/audit/reference/rewrite-guide.md:32`, "Never rewrite a
quotation"). The scanner does not exempt blockquotes the way it exempts fenced code.

### Form C, quoted teaching corpus, 114 candidates, rejected

Every candidate under `plugins/songwriting/context/pat-pattison/research/`. That tree is a
book-distillation corpus. `repetition.md:1-5` states its basis: "Pat Pattison, *Writing Better
Lyrics* (2009), Chapter 6 and Chapter 9, plus *Essential Guide to Lyric Form and Structure*
(1991), Chapter 7". The imperatives in it are a named author's instructional voice, transcribed
under attribution. `Do not use cliché rhymes` and `Do not pluralise either verb` are Pattison's
sentences, not this repo's. Rewriting them breaks the attribution.

Functionally this tree is vendor material that happens to sit outside
`plugins/*/skills/*/vendor/**`, so the sweep's vendor exclusion misses it. Same reasoning applies
to `plugins/tdd/skills/principles/reference/anti-patterns-khorikov.md` and
`docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md`, which the mechanical test
does not catch because they are single files rather than a tree. Those two sit in form E and were
rejected there individually.

### Form D, rubric exclusion clause, 26 candidates, rejected

`Must NOT flag: a benchmark named as a pointer with no figure attached`
(`plugins/claude-config/skills/audit-instructions/reference/criteria.md:1194`) and its 25 siblings.
These are a detector's declaration of its own non-scope. The prohibition *is* the content: an
exclusion list has no positive form short of inverting the entire rubric into an inclusion list,
which is a different document. This is the skill's own "a hard guardrail that cannot be phrased
positively is not a finding" carve-out, reached by a route the keyword gate does not cover.

### Form E, remainder, 1031 candidates

Sample: 60 rows drawn at random from the 1031, each read with its surrounding paragraph. Two calls
were revised on a second read with wider context; the rates below are post-revision.

| Sub-form | n in sample | share | Decision |
|---|---:|---:|---|
| E1: positive already present in an adjacent sentence or clause | 43 | 71.7% | Reject |
| E2: hard guardrail the keyword gate missed | 10 | 16.7% | Reject |
| E3: genuine unpaired prohibition with a clean positive rewrite | 7 | 11.7% | Finding |

**E1, the dominant form.** The scanner classifies one accumulated sentence. The house style writes
the prohibition and its positive as *two* sentences, or puts the positive in the preceding clause.
Every one of these already satisfies the shape's intent and none needs an edit:

- `plugins/discipline/skills/reuse-or-replace/SKILL.md:117`, "Do not apply this skill to a
  build-vs-buy or which-library decision. Route it there."
- `plugins/machine-health/skills/audit/SKILL.md:91`, "**Never write into the plugin install
  directory.** All generated state routes to `<StateBase>` / `<OutputBase>`"
- `plugins/discipline/skills/do-your-research-deep/SKILL.md:135`, "empty, an unexpanded token, and
  an unrecognized value all mean `tiered`. Never error on a bad value."
- `docs/conventions/detector-findings/README.md:485`, "**Write your own file. Never append into
  another producer's.**"

Widening the accumulation window to the paragraph would remove roughly 70% of this form's volume.

**E2, hard guardrails the keyword gate missed.** The scanner's guardrail carve-out is a fixed word
list (`secret`, `credential`, `force-push`, `rm -rf`, `destructive`, `production`, `security`, and
so on). This repo's hard boundaries cluster in a register that list does not name:

| Register | Example |
|---|---|
| No-fabrication / honesty | `plugins/adhd/skills/clarify/SKILL.md:127`, "Never claim a decision table was rendered when only prose was produced" |
| Do not reconstruct from training data | `plugins/x/skills/read/SKILL.md:243`, "Never present a truncated chain as complete, and never fill a gap from memory" |
| Quote integrity | `plugins/ai-slop/skills/audit/reference/rewrite-guide.md:32`, "Never rewrite a quotation" |
| Read-only contract | `plugins/repo-fleet-hygiene/skills/apply/SKILL.md:27`, "Never run without `--plan-file` pointing at a prior audit plan" |
| First-invocation destructive gate | `plugins/repo-hygiene/skills/clean/SKILL.md:108`, "**Never `--apply` on first invocation.**" |
| Third-party terms of service | `plugins/ai-briefing/skills/generate/SKILL.md:31`, "Do not refresh following graphs or profile metadata. X's current terms expressly prohibit crawling" |

Each is a boundary whose positive form loses the constraint, which is the skill's own stand-down
condition.

## Why this lane does not extrapolate E3 to its population

7 of 60 projects to roughly 120 of the 1031 remainder, with a 95% Wilson interval of about 60 to
228. This lane deliberately does **not** issue that population as findings.

The grounds are measured, not stylistic. `docs/specs/d1-model-already-knows-measurement.md` is a
419-line measurement record over 895 files of this same corpus, adjudicating 185 sampled sentences
against a comparable cue-based predicate. Its result:

> **94.1%** (174/185) ... resolving *every* contested call **in the proxy's favour**.
> ... Not one sentence in 185 was an unambiguous no-op.

and its explanation of the failure, which is about this corpus rather than about that one
predicate:

> 54.8% of the flagged population is in hard-boundary register, `never`, `must` (which subsumes
> `must not`), `do not`, `don't`, `cannot` ... because the house style writes its most load-bearing
> rules as bare imperatives, precisely because those rules are universal

That is the same population `negation` flags, and it is the same register. In a corpus where the
bare negative imperative is the measured house form for a load-bearing boundary, applying a form
decision to 1031 unread rows at 11.7% precision would generate roughly 910 spurious edits against
instruction surfaces. The verdict that spec reaches for its own class, "never rule on it", is not
transferable wholesale, because `negation`'s treatment is a rewrite rather than a deletion and so
fails softer. But it fixes the posture: **for this shape, form membership is not sufficient
evidence to emit a finding. Only an individually read instance is.**

Consequence, stated plainly: this lane's E3 recall is 7 of an estimated 120. See "Recall limits".

## Findings

All Tier 2. Treatment per the shape table: rewrite to the positive target the prohibition implies,
or pair the positive into the same sentence. Never a deletion; the constraint survives.

### 1. `docs/PLUGIN-PHILOSOPHY.md:546`

> Do not swallow errors or claim success when the promised result was not produced.

No positive anywhere in the paragraph; the preceding sentence describes advisory hook behavior.

**Remediation.** Replace with: `Surface every error, and report the result the run actually
produced.`

### 2. `plugins/review/skills/fanout/context/fix-pass-mode.md:142`

> - **NEVER route correctness findings to `/simplify`.**

A whole bullet with no positive. The destination for a correctness finding is left unstated, which
is the cost: a reader who has not memorized the fix-pass routing has no disposition.

**Remediation.** Replace with: `- **Route correctness findings to the fix pass. `/simplify` is
quality-only and does not hunt bugs.**` Confirm the destination against the fix pass's own routing
table before applying.

### 3. `plugins/instruction-placement/skills/realign/context/apply-recipes.md:70`

> **Never** put an `@import` in the body of a path-scoped rule. The import inlines at session start and
> defeats the scoping — the move would read as a saving and not be one.

The second sentence is rationale, not an alternative. A reader who needs shared content in a
path-scoped rule is told what fails and not what works.

**Remediation.** Pair the positive into the same sentence: `**Cite** the shared file from a
path-scoped rule by path, never with an `@import`: the import inlines at session start and defeats
the scoping.` Keep the existing second sentence.

### 4. `plugins/ai-briefing/skills/generate/context/execution-flow.md:92`

> 4. Do not use Playwright or another browser provider for source collection.

Step 3 immediately above already carries the positive with an `only`: "Use Playwright only to open
generated local HTML for PDF rendering, screenshots, and layout validation." Step 4 restates its
complement as a separate numbered step.

**Remediation.** Fold step 4 into step 3 as the paired form: `Use Playwright only to open generated
local HTML for PDF rendering, screenshots, and layout validation, never for source collection.`
Renumber the steps that follow. This is a merge, not a deletion: the constraint stays on the page.

### 5. `plugins/adhd/skills/shape/SKILL.md:39`

> 1. **Working memory is small.** Anything off-screen is gone. Never ask the
>    reader to "keep in mind" something stated earlier.

The positive form is the skill's own standing rule, stated in its `description` as "restate state
across turns", so the rewrite loses nothing and makes the bullet self-contained.

**Remediation.** Replace the third sentence with: `Restate any earlier state the reader needs, in
the current response.`

### 6. `plugins/source-control/skills/babysit-prs/SKILL.md:321`

> Never block a safe iteration on the engine's absence.

Sentence-final in a paragraph about a missing merge-gate engine. The preceding clause covers
reporting, not proceeding, so the positive is genuinely absent.

**Remediation.** Replace with: `Let a safe iteration proceed when the engine is absent, reporting
merge-readiness as unchecked.`

### 7. `plugins/source-control/skills/babysit-prs/reference/loop.md:629`

> - **Do not skip verification steps.** The D5/D6/D7 verification sub-steps exist because model
>   memory is unreliable across compaction boundaries.

The bullet's bolded lead is the instruction; the rest is rationale. The named sub-steps make the
positive trivially available.

**Remediation.** Replace the bolded lead with: `- **Run the D5/D6/D7 verification sub-steps on
every pass.**` The rationale sentences survive verbatim.

## Detector defects worth reporting

1. **Table rows still select** (30 cases). The `|` opener guard runs after soft-wrap accumulation
   has already stripped the leading pipe from a wrapped row, so the skill's stated exemption does
   not hold in practice.
2. **Blockquotes are not exempt** (28 cases). Fenced code and frontmatter are exempt; `>` lines are
   not, so quoted prohibitions flag.
3. **The accumulation window is one sentence, but the pairing is usually two.** 71.7% of the
   adjudicated sample has its positive in the adjacent sentence. Widening the paired-positive
   search to the enclosing paragraph or list item would cut this shape's volume by roughly two
   thirds at no recall cost that this sample can see.
4. **The guardrail keyword list under-covers this fleet's registers.** Adding `claim`, `invent`,
   `fabricate`, `from memory`, `training data`, `quotation`, `read-only`, and `terms of service`
   would absorb most of form E2.

## Cross-lane observations

- **L3-ssot.** The `#571` displacement-bypass sentence is carried near-verbatim in
  `plugins/source-control/skills/babysit-prs/SKILL.md:199` and
  `plugins/source-control/skills/babysit-prs/reference/runbook-cycle.md:61`. Duplication is L3's.
- **L6-compress.** Form E1's two-sentence prohibition-then-positive pattern is a compression
  target as much as a noise one. L6 owns whether to merge them for brevity; this lane's interest
  ends once the positive is present somewhere adjacent.
- **Corpus classification.** `plugins/songwriting/context/pat-pattison/research/**` (114 of this
  shape's candidates) is quoted third-party teaching material sitting outside the sweep's vendor
  exclusion. Worth a manifest reclassification for every lane, not only this one.
