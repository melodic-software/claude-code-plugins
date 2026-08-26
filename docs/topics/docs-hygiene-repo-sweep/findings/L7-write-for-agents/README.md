# L7 · `write-for-agents` · roll-up

Lane: audit the 997 `audience=AGENT` rows of `inventory/manifest.tsv` against
`docs-hygiene:write-for-agents` doctrine. Read-only; every finding is a remediation spec for the
wave 3 in-file prose pass.

`predicates.md` is the rubric and was written before any file was audited. Read it first; this file
assumes its P-numbers, decidability grades, and S1/S2/S3 severity scale.

Verbatim source quotes and proposed replacements in every group file are in fenced `text` blocks,
never blockquotes, so `markdownlint` MD029 does not fire on a preserved step number and the
`markdown-format` hook does not restyle spacing around inline code inside a quote.

## Method

The skill has no scan mode, so the lane turned its body into 21 predicates and built one mechanical
detector per emitting predicate over the 997-row slice. Every cue hit was then adjudicated by
reading the file. No finding in this directory rests on a cue alone.

The calibration is `docs/specs/d1-model-already-knows-measurement.md`, which measured a cue-based
predicate over essentially this corpus at a 94.1% false-positive rate and ruled *"never rule on
it."* Its mechanism generalizes: a cue whose target property is not readable off the text produces
an inverse detector, preferentially surfacing the passages whose "fix" is most damaging. Two
predicates in this lane reproduced that result exactly and emit nothing as a result (P16, P9).

## Predicate results

| ID | Predicate, short | Cue hits | Files | Adjudicated | Filed | Why |
|---|---|---:|---:|---|---:|---|
| P3 | Pointer front-loads the leading word | 76 | 48 | all 76 | 39 | 8 individual + 31 batched |
| P5 | Mirror-maintenance pointer masks low cohesion | 44 | 43 | all 44 | 0 | Every hit is `mirror` meaning "match the shape of", or a doc refusing duplication |
| P6 | Procedure not interrupted by reference material | 25 | 25 | all 25 | 0 | 0 survive a heading-boundary and list-continuity guard |
| P7 | Step does not defer a needed fact to a distance | 163 | 116 | 33 `T2` | 2 | 31 of 33 name their target section; 2 do not |
| P9 | Every step carries a completion criterion | 162 | 162 | 12 `T2` read in full | 0 | See "P9 and P16" below |
| P10 | Criterion is a goal-state, not the attempt | 0 | 0 | n/a | 0 | No instance in the corpus |
| P12 | Agent does its own legwork | 6 | 6 | all 6 | 0 | All 6 are last-rung fallbacks after the agent's own resolution failed |
| P14 | Invocation-mode split cites the rubric | 1 | 1 | 1 | 0 | Not a split decision; the convention and the skill already cross-link |
| P16 | Positive leading word where one is available | 1178 | 490 | 30-row `T2` sample | 0 | See "P9 and P16" below; owned by L5 |
| P18 | No hand-written glossary | 6 | 6 | all 6 | 0 | All 6 are out of scope of the skill the doctrine routes to; the doctrine is what needs the fix |
| P21 | Harness load-semantics facts stated correctly | 456 | 132 | 5 fact families | 0 | Zero errors; see "P21" below |

P1, P2, P11, P19 emit nothing by design (not auditable). P4, P8, P13, P15, P17, P20 emit nothing
because another lane owns them.

## Findings by group and tier

| Group | Findings | S1 | S2 | S3 | File |
|---|---:|---:|---:|---:|---|
| `B-cc-config-ops` | 5 | 0 | 5 | 0 | `B-cc-config-ops.md` |
| `D-work-planning` | 1 | 1 | 0 | 0 | `D-work-planning.md` |
| `F-quality-verify` | 2 | 0 | 1 | 1 | `F-quality-verify.md` |
| `H-knowledge-research` | 1 | 0 | 1 | 0 | `H-knowledge-research.md` |
| `I-songwriting` | 1 batch (31 lines) | 0 | 0 | 1 | `I-songwriting.md` |
| `J-toolchain-platform` | 3 | 0 | 0 | 3 | `J-toolchain-platform.md` |

Totals: 13 filed findings covering 41 lines. 1 `S1`, 7 `S2`, 5 `S3`. By tier: 8 on `T2` surfaces, 5
on `T3`. Groups `A`, `C`, `E`, `G`, `M` produced no findings and have no file, per the sweep's
no-quota rule.

By predicate: P3 accounts for 11 of the 13 (8 individual, 3 batched into 1); P7 for 2.

## P9 and P16: measured, not filed

These two are the lane's largest cue populations and its two deliberate non-emissions. Recording the
measurement matters more than the zero, because a later lane will otherwise re-run them.

**P16, prompt the positive.** 1178 cue hits across 490 files, of which 473 are `T2`. A 30-row `T2`
sample, adjudicated by reading each in its file:

| Verdict | n |
|---|---:|
| Segmentation artifact (mid-sentence wrap, or `No <X>` as a list or table label) | 12 |
| Hard boundary where the positive form loses the constraint (doctrine-exempt) | 12 |
| Prohibition paired with its positive in the adjacent sentence rather than the same one | 6 |
| Genuine unpaired prohibition with a lossless positive form available | 0 |

0 of 30. This is the d1 result reproduced: the fleet writes its most load-bearing rules as bare
negative imperatives precisely because they are universal, so the cue correlates with the passages
that must not be touched. The lead-word distribution over all 1178 (`no` 451, `never` 429, `do not`
220, `don't` 59, `avoid` 19) is dominated by `no`, which is mostly not a prohibition at all.

**P9, completion criteria.** 162 files carry an ordered procedure with no explicit done-cue in the
procedure span. 12 `T2` procedures were read end to end. In every one, the criterion is carried by
the step's stated output shape rather than by a literal "the step is complete when Y appears"
clause. `plugins/session-flow/skills/keep-going/SKILL.md:33-107` is representative: step 6 is
`**Report.** One list: recovered, restarted, still-running, and lost / unrecoverable`, which fixes
the observable without using the doctrine's phrasing. Filing 162 findings on that basis would be a
style edit dressed as a defect, and would trip the same premature-completion risk it claims to fix
by encouraging authors to bolt a criterion clause onto a step that already has one.

Both are recorded so the reconciliation pass can see the shape and the number, not so it can act on
them.

## P21: harness load-semantics facts

Five fact families were checked against
`plugins/docs-hygiene/skills/write-for-agents/reference/agent-doc-surfaces.md`: `@` import cost,
`/compact` re-injection, `MEMORY.md` truncation, scope order, and context-is-not-enforcement. Zero
contradictions across 132 files.

Worth reporting as a positive: the fleet has a de facto agreement chain on the one fact most often
got wrong elsewhere. `claude-memory/skills/audit/reference/criteria.md:84` and `:131`,
`claude-config/skills/audit-instructions/reference/criteria.md:204`,
`docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:26`, and the
`write-for-agents` reference itself all independently state that `@path` imports do not defer
loading. `instruction-placement/context/verified-mechanics.md:33` refines it (an import inside a
*nested* `CLAUDE.md` defers with its parent) without contradicting it. No lane action needed.

## Doctrine conflicts

### C1 · The skill disclaims the entire `T2` stratum this lane was pointed at

`plugins/docs-hygiene/skills/write-for-agents/SKILL.md`, "What this skill does NOT do":

```text
- **Does not author skills**, a SKILL.md is `playbooks:skill-authoring` + `skill-quality:check`
  territory; this skill's doctrine reaches skill authors through those surfaces.
```

All 250 `T2` rows in the `AGENT` slice are either a `SKILL.md` (237) or an agent definition (13).
The tier that carries this lane's highest severities is the tier the skill's own scope statement
routes elsewhere. 8 of the 13 filed findings land on it.

This is a conflict to resolve, not a defect to rule on. Two readings are both defensible: the
disclaimer is about *authoring a new skill* (in which case conformance-auditing an existing one is
in scope), or it is about the surface class (in which case these 8 findings belong to
`skill-quality`). The lane did not rule. Recommendation for wave 2: treat the 8 `T2` findings as
advisory and get `skill-quality:check`'s concurrence before wave 3 applies them. All 8 are pointer
phrasing and step co-location, none touches frontmatter, so concurrence should be cheap.

### C2 · "Never hand-write a glossary entry" overshoots the skill it routes to

`write-for-agents/SKILL.md`, "After writing":

```text
- Resolved or coined a domain term? Invoke `/domain-driven-design:curate-language` via the
  Skill tool (if that plugin is installed), never hand-write a glossary entry.
```

The prohibition is unqualified. The skill it routes to is not.
`plugins/domain-driven-design/skills/curate-language/SKILL.md` scopes itself to "a consuming
project's ubiquitous-language glossary" and excludes "passive glossary lookup, general dictionary
definitions". Its body adds: "Merely reading the nearest glossary so another skill uses the right
words is a one-line habit and does not require this workflow."

Six `AGENT` files carry a hand-written vocabulary section that the prohibition catches and the
routing target does not accept:

- `plugins/event-storming/skills/methodology/reference/glossary-and-tools.md:3` (`## Glossary`)
- `plugins/work-items/reference/execution-shape.md:111` (`## Vocabulary`)
- `plugins/review/context/severity.md:28` (`## Vocabulary`)
- `plugins/architecture/skills/improve/research/deepening/vocabulary.md:7` (`## Terms`)
- `plugins/planning/skills/design/SKILL.md:144` (`## Terminology pass`)
- `plugins/songwriting/context/pat-pattison/research/book-references.md:182`

None of these is a consuming project's resolved domain vocabulary; each defines the terms its own
skill uses. The defect is in the doctrine sentence, not in the six files, so no group file lists
them. Proposed replacement for the doctrine line:

```text
- Resolved or coined a term in the **consuming project's** domain? Invoke
  `/domain-driven-design:curate-language` via the Skill tool (if that plugin is installed) rather
  than hand-writing the entry. A skill defining its own working vocabulary is out of that skill's
  scope and stays where it is.
```

That edit is to a `docs-hygiene` skill body and is outside this lane's read-only wave 1 boundary.
Routed to the orchestrator.

### C3 · Resolved overlap, recorded so it is not re-litigated

`plugins/docs-hygiene/skills/audit-noise/SKILL.md:61` already implements P15 and P16 as its
`negation` shape, names itself the audit-side completion of this doctrine, and carries the carve-out
that the 30-row sample proved essential:

```text
The write-side rule this completes is [`/docs-hygiene:write-for-agents`](../write-for-agents/SKILL.md) "Prompt the positive". **A hard guardrail that cannot be phrased positively is not a finding** and is never flagged
```

This is a clean handoff, not a contradiction. `L5-noise` owns the axis with a shipped detector and
the right exemption; `L7` emits nothing on it. Same shape for P14: `docs/conventions/invocation-mode/README.md:151`
already states that `docs-hygiene:write-for-agents` points there for its when-to-split doctrine, and
the skill body does. The link is bidirectional and current.

## Audience reclassifications proposed

### R1 · 62 fixture rows are neither audience (they are test data)

60 rows match `evals/fixtures/` and 2 match `scripts/fixtures/`, all currently `audience=AGENT`.
Several are **deliberately defective specimens** that anchor a passing eval. Applying doctrine to
them would break the tests they exist for. The clearest cases:

- `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/SKILL.md`
  (tier `T2` in the manifest) is the negative fixture for the sibling lane's own detector.
- `plugins/docs-hygiene/skills/write-for-agents/evals/fixtures/draft-rule.md:5` contains
  `See the migrations doc.`, a textbook P3 violation, on purpose.
- `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/negation-shapes.md` exists to carry
  negations.
- `plugins/docs-hygiene/skills/compress/evals/fixtures/verbose-onboarding-snippet.md` exists to be
  verbose.

Proposal: add a `FIXTURE` audience value, or an `exclude` flag, and move all 62 out of every lane's
slice. This affects `L5`, `L6`, `L7`, and `L8` identically, so it belongs to the orchestrator rather
than to this lane. The manifest is regenerated, never hand-edited, so the change is to the generator.

L7 already excluded them from its filed findings; the P3 detector's first two hits are fixtures.

### R2 · 4 `NOT_IMPLEMENTED.md` rows are `HUMAN`

- `plugins/machine-health/skills/audit/scripts/linux/NOT_IMPLEMENTED.md`
- `plugins/machine-health/skills/audit/scripts/macos/NOT_IMPLEMENTED.md`
- `plugins/machine-health/skills/audit/references/linux/NOT_IMPLEMENTED.md`
- `plugins/machine-health/skills/audit/references/macos/NOT_IMPLEMENTED.md`

Each is a porting checklist addressed to a contributor who will write the missing scripts, not
instruction text an agent executes. They route to `L8-write-for-humans`. All four are `T3`, so the
reclassification changes ownership rather than severity.

### R3 · Manifest and PLAN disagree on the slice size

`PLAN.md` states `AGENT` is 994 files; `inventory/manifest.tsv` has 997 rows with `audience=AGENT`
(3 `T1`, 250 `T2`, 744 `T3`). The lane audited the 997 in the manifest, since PLAN.md names the
manifest as the single source of truth. Flagging so the orchestrator can reconcile the prose.

## Cross-lane observations

One line each, per the lane boundary.

- **L2-progressive-disclosure**: the four `audit-install-state` pointers, the three payload-free
  songwriting pointers, and `discovery/skills/trace-intent/SKILL.md:198` are blind-pointer candidates
  on the P4 axis L2 owns; if L2 files them, its rewrite supersedes the P3-only fixes here.
- **L5-noise**: `plugins/docs-hygiene/skills/write-for-agents/reference/agent-doc-surfaces.md`
  carries 11 em dashes in a non-vendor `docs-hygiene` instruction surface, which
  `.claude/rules/vendor-docs-are-not-style.md` and the house style guide both forbid; the sibling
  `SKILL.md` has zero.
- **L6-compress**: no compression findings were formed; P3 fixes here add 2 to 5 words per line and
  should be applied before any compression pass measures the file.
- **L1-derivability**: the 62 fixture rows in R1 are derivability-immune (they are test inputs, not
  claims) and should be excluded there too.
- **`playbooks:skill-authoring` / `skill-quality:check`**: conflict C1 needs their concurrence on 8
  `T2` findings; the lane did not enter their territory and touched no frontmatter.

## Recall limits

Stated honestly, because a conformance verdict against authoring doctrine is a weaker instrument
than a scanner and this record should not be read as one.

1. **No subagents.** No `Agent` or `Task` tool exists in this lane's context and `ToolSearch` does
   not surface one. The whole lane ran serially in one context. Every substitute for fan-out was a
   mechanical detector plus sampled adjudication, which trades recall for precision.
2. **Cue-bounded recall on every predicate.** P3 recall is bounded by a fixed routing-verb list
   (`See`, `Refer to`, `Consult`, `For more|further|additional|details|complete|the full|a full`).
   A pointer opening `Look at`, `Check`, or `Head to` is missed. The same limit applies to P5, P7,
   P12, and P18. Precision was verified by reading; recall was not measured at all.
3. **`T3` adjudicated by sample, `T2` by census, for P7 and P9.** All 33 `T2` P7 hits and 12 of 44
   `T2` P9 procedures were read. The 130 `T3` P7 hits and all 118 `T3` P9 hits were not. A `T3`
   violation of either predicate is likely present and unfiled.
4. **P16 rests on 30 of 1178.** The 0/30 result is strong enough to justify not emitting, and it
   agrees with a prior 185-row measurement on the same corpus, but it is a sample. It is also moot:
   `L5` owns the axis with a shipped detector.
5. **P21 checked 5 fact families, not the space of harness claims.** A wrong claim about a surface
   the reference does not tabulate (workflows, output styles, hook `additionalContext` caps) would
   not have been caught.
6. **Four predicates are not auditable and were not attempted.** P1 (observed-stumble evidence), P2
   (which budget was spent), P11 (post-completion obligations), P19 (authoring-session routing). P1
   in particular is the class `docs/specs/d1-model-already-knows-measurement.md` routed to
   `claude-config:unhobble` and told this fleet never to rule on from text. This lane did not.
7. **Doctrine conformance is a weaker verdict than a scanner's.** Every filed finding cites a
   passage of the skill body and a `path:line`, so each is checkable. None is a measurement.
