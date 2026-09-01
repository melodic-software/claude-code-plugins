# Vertical decisions V2 to V7, resolved in-session

The corpus work was organized into seven verticals. V1 (unhobbling) was resolved by the signed-off
answer set in the topic's decision contract, which is contract tier and therefore pruned before
merge, surviving as the `<details>` paste in its pull request. The remaining six were originally routed to "future
interview rounds", which was a mistake: the evidence those rounds would have consumed lived only in
an untracked memory tier, so a future session would have inherited the questions without the
answers. They are resolved here instead, on the evidence gathered while it was in hand.

Each entry states the decision, its basis, and what actually changes. Several resolve to "no change,
and here is why", which is a real outcome for a corpus pass over a repo that already does most of
this.

## V2. Progressive disclosure

**Decision: no new mechanism; the corpus's rationale is adopted as citation, not as a rule.**

The repo already implements the pattern the sources advocate. `AGENTS.md` carries a load-on-demand
rules table with path triggers, skills carry their own progressive disclosure through reference
subdirectories, and `context-budget:audit` and `docs-hygiene:audit-progressive-disclosure` already
own the measurement. What the corpus adds is a *why* worth citing when those surfaces are
questioned: the attention-budget and context-rot mechanism, and the guiding principle that the
target is the smallest set of high-signal tokens rather than the shortest document. Both are
recorded in [`corpus-knowledge.md`](corpus-knowledge.md) with their sources.

One caveat the sources do not supply and this repo already knows: its own rules table documents that
the path trigger does not fire inside subagents and can lapse after a compaction. Progressive
disclosure is therefore a budget mechanism here, never a guarantee of delivery, and the corpus's
enthusiasm does not change that.

**Changes: none to any skill.** The rationale lands in the graduated corpus docs.

## V3. Interface design over examples

**Decision: adopt for tool and parameter surfaces; explicitly do not adopt for teaching skills.**

The newer source's claim is that worked examples constrain a capable model's exploration space, and
that expressive parameters (an enum, one behavioral constraint line) teach usage better than a
worked example does. The older source from the same publisher advises the opposite, strongly, for
few-shot prompting. That reversal is real and generational, not a contradiction to resolve by
picking a winner. See [`critical-apparatus.md`](critical-apparatus.md), cross-source tensions.

Resolution for this repo:

- **Tool and parameter surfaces**: prefer an expressive interface over a worked example. This is
  already the house pattern (enums, one-line constraints in tool descriptions); no edit needed.
- **Teaching skills** (`education:*`, `songwriting:*`, the methodology skills): examples are the
  content, not scaffolding around it. The reversal does not reach them, and a future trimming pass
  citing the corpus at them is misapplying it. Recorded here so that misapplication has a written
  answer.
- **Skill bodies generally**: a worked example that demonstrates a *format the skill requires*
  stays. One that demonstrates *how to think about the task* is a trimming candidate on the normal
  criteria, not because the corpus says so.

**Changes: none.** The boundary is the deliverable.

## V4. Placement: which surface an instruction lives on

**Decision: the settled facts are recorded; no placement doctrine is minted.**

The corpus's per-surface guidance (system prompt, CLAUDE.md, skills, references, memory) maps onto
machinery this repo already has in `instruction-placement:*`, whose Gate 0 and routing rubric are
more specific than the article's prose. Two upstream facts do change what the repo may say, and both
are now recorded in [`corpus-knowledge.md`](corpus-knowledge.md):

- The `#` memory hotkey was **removed** (Claude Code changelog v2.0.70), not merely de-emphasized.
  Any repo text implying it exists is wrong.
- The Developer Platform memory tool and context editing are **not exposed natively by Claude Code**
  (its analogues are auto-memory and compaction). A placement doctrine citing "the memory tool" as
  a harness surface would be false.

The article figure's six-layer stack (prompt, references, system prompt, CLAUDE.md, skills, memory)
is carried in the corpus doc as figure-borne, with the note that the article's own body never
covers the memory layer.

**Changes: none to `instruction-placement`.** The register from Q2 is the one placement-adjacent
artifact this integration adds, and it lands as a convention rather than as doctrine.

## V5. Rich references over simple specs

**Decision: adopted as practice already in force; one gap named and left open deliberately.**

The claim is that a spec is better expressed as code, a test suite, an HTML artifact, or a rubric
than as prose. This repo's planning pipeline already does the strong form of this: PLAN.md briefs
carry acceptance criteria, the verification plugins carry rubrics, and the dynamic-workflows
capability (documented upstream, see [`linked-sources.md`](linked-sources.md)) supplies the
verifier-agent pattern the source points at.

The gap: this repo has no convention for *mockups or visual references* as specs, because it ships
no UI. The source's strongest example (an HTML mockup beats a description or a screenshot) has no
consumer here. Named rather than invented.

**Changes: none.** Adoption is a no-op because the practice predates the corpus.

## V6. Long-horizon techniques

**Decision: annotate the existing orchestration guidance; do not mint a notes-file convention.**

- **Condensed returns**: `session-flow:orchestrate` already required compressed verdicts. It now
  carries the upstream magnitude (roughly 1,000 to 2,000 tokens returned from an exploration that
  may span tens of thousands) and the reconciled token-multiplier figures, since the repo's own
  3-10x line and the upstream ~15x measurement were in tension. Shipped in this change.
- **Structured note-taking**: the sources recommend a persistent notes file whose test is
  reset-survival. This repo already implements the pattern under different names (checklists,
  handoff artifacts, per-skill ledgers, the topic memory slice), and a new cross-cutting convention
  would collide with the topic-docs redesign already locked and in flight. **Not adopted**, and the
  reason is sequencing, not disagreement.
- **Compaction**: harness-owned. The corpus's tuning guidance (maximize recall first, then trim for
  precision; clear tool results before summarizing) applies to anyone *building* an agent loop, not
  to this repo's consumers. Recorded, not adopted.

**Changes: the orchestrate annotation, shipped here.**

## V7. Corpus meta and custody

**Decision: graduate the knowledge now; keep the raw slices untracked; record the custody findings
as a convention-level input rather than a new convention.**

The original answer deferred graduation to a later pass. That was wrong for the same reason the
whole deferral posture was wrong: the memory tier does not survive. Resolved as:

- **Graduated** into this directory: the corpus knowledge base, the critical apparatus, the linked
  sources, and this decisions record. These are the durable artifacts.
- **Not graduated**: the byte-verified digest slices, pin manifests, verification verdicts, and
  reconciliation tables. They are process evidence for a run that has already been adjudicated, and
  committing 800K of them would trade a real cost for no reader's benefit. Their *conclusions* are
  in the graduated docs; the fact that they existed and what they proved is recorded in
  [`corpus-knowledge.md`](corpus-knowledge.md).
- **Custody findings** (silent page revision, figure-only evidence, provenance stripping through
  text extraction, link defects, contradictory vendor lists, the documented generational reversal in
  official docs) are recorded in the corpus doc, and the one with a mechanism behind it, the silent
  revision, is filed against the `upstream-drift` convention's deferred content-hashing decision as
  near-miss evidence rather than as a new convention.

**Changes: this directory's four documents, plus the upstream-drift changelog entry shipped
separately.**
