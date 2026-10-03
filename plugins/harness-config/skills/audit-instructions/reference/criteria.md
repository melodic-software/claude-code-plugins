---
version: 1.27.0
last-updated: 2026-10-02
---

# Instruction-Audit Criteria

## Contents

Look up a specific check by ID: run `grep -n '^### I<N>:'` over this file.

- [Sources](#sources)
- Checks
  - [I1: Line-necessity bar](#i1-line-necessity-bar)
  - [I2: Length and skimmability](#i2-length-and-skimmability)
  - [I3: Broad-applicability placement](#i3-broad-applicability-placement)
  - [I4: Inferable or redundant content](#i4-inferable-or-redundant-content)
  - [I5: Rule-to-hook or delete](#i5-rule-to-hook-or-delete)
  - [I6: Bare prohibition to positive reframing](#i6-bare-prohibition-to-positive-reframing)
  - [I7: Reason with the request](#i7-reason-with-the-request)
  - [I8: Model-era re-audit](#i8-model-era-re-audit)
  - [I9: Example hygiene](#i9-example-hygiene)
  - [I10: Reasoning-echo directives](#i10-reasoning-echo-directives)
  - [I11: CLI over MCP where equivalent](#i11-cli-over-mcp-where-equivalent)
  - [I12: Stale or misattributed harness-capability claim](#i12-stale-or-misattributed-harness-capability-claim)
  - [I13: Citation form that does not load](#i13-citation-form-that-does-not-load)
  - [I14: Retrieval of an already-loaded surface](#i14-retrieval-of-an-already-loaded-surface)
  - [I15: Cross-surface instruction conflict](#i15-cross-surface-instruction-conflict)
  - [I16: Definition-site locality](#i16-definition-site-locality)
  - [I17: Thinking disabled where the model forbids it](#i17-thinking-disabled-where-the-model-forbids-it)
  - [I18: Thinking blocks altered on the way back to the model](#i18-thinking-blocks-altered-on-the-way-back-to-the-model)
  - [I19: Restated external benchmark figure with no recheck trigger](#i19-restated-external-benchmark-figure-with-no-recheck-trigger)
  - [I20: Prefilled assistant response](#i20-prefilled-assistant-response)
  - [I21: Effort level pinned across a model change with no re-sweep](#i21-effort-level-pinned-across-a-model-change-with-no-re-sweep)
  - [I22: Model-routing doctrine with no baseline named](#i22-model-routing-doctrine-with-no-baseline-named)
  - [I23: Context-budget directive to stop, summarize, or hand off](#i23-context-budget-directive-to-stop-summarize-or-hand-off)
  - [I24: Instruction relying on silent generalization](#i24-instruction-relying-on-silent-generalization)
  - [I25: Sampling parameter prescribed where the model rejects it](#i25-sampling-parameter-prescribed-where-the-model-rejects-it)
  - [I26: Generic negative steering on open-ended design briefs](#i26-generic-negative-steering-on-open-ended-design-briefs)
  - [I27: Effort lowered to shorten the response](#i27-effort-lowered-to-shorten-the-response)
  - [I28: Over-aggressive trigger emphasis and blanket tool defaults](#i28-over-aggressive-trigger-emphasis-and-blanket-tool-defaults)
  - [I29: Body prose that restates the always-in-context description, or a sibling section](#i29-body-prose-that-restates-the-always-in-context-description-or-a-sibling-section)
  - [I30: Dated verification stamp with no recheck trigger](#i30-dated-verification-stamp-with-no-recheck-trigger)
  - [I31: Migration-relative phrasing in skill bodies and the files they load](#i31-migration-relative-phrasing-in-skill-bodies-and-the-files-they-load)
  - [I32: Routing text that names a skill that does not resolve](#i32-routing-text-that-names-a-skill-that-does-not-resolve)
  - [I33: Sibling-file meta-commentary](#i33-sibling-file-meta-commentary)
  - [I34: Maintainer rationale inside model-facing YAML comments](#i34-maintainer-rationale-inside-model-facing-yaml-comments)
  - [I35: Settled-answers instruction where later steps revise earlier ones](#i35-settled-answers-instruction-where-later-steps-revise-earlier-ones)
  - [I36: Tool-discouraging language](#i36-tool-discouraging-language)
  - [I37: Harness text after every tool result](#i37-harness-text-after-every-tool-result)
- [Stopping condition](#stopping-condition)
- [Out-of-catalog defects](#out-of-catalog-defects)
- [AGENTS.md content-home advisory](#agentsmd-content-home-advisory)
- [Output format](#output-format)

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy: the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers.** Treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; **a change to any page listed under Sources
below**. Every check that cites a source cites one of those pages, so the trigger set is the source
set. Naming a subset would leave the harness-behavior rows depending on pages nothing watches. A
row whose Source line reads `none` for a categorical absence, where no official page states the
rule, has nothing of its own to go stale; a sourceless row that instead calibrates against page
content (the Stopping condition's carve-out phrasing) is staled by the pages it calibrates against,
which the catalog-wide trigger already covers. One staleness event fires the whole catalog, not the
check that noticed it. Model-specific pages, the per-model prompting guides under Sources, are
superseded on each model generation.

**Per-row verification stamps.** A row whose firing rule acts on a volatile upstream *literal*,
such as a level name, a model range, or a type predicate, keeps that literal as its own setting and
additionally carries the record that decision needs: the decision in our words, a pointer to the
exact upstream section, an as-of date, and a recheck trigger naming an observable event, with no
upstream text (the shape is `docs/conventions/upstream-drift/README.md` in this monorepo; in a
standalone install those parts, not the path, are the requirement). A row whose Source line only
names its page and section, and whose firing rule acts on no such literal, carries no stamp: the
catalog-wide trigger already covers it.

A per-row stamp **supplements** the catalog-wide trigger above; it never replaces or narrows it.
The catalog trigger already fires every row on any Sources change, so a per-row trigger adds no
coverage the Sources set lacks, since a value change on a Sources page *is* a change to that page. What
it adds is **specificity about what to re-read**: it names the literal that row restates and the
event that would move it, so a re-verification pass goes straight to that value instead of
re-reading the page to find what mattered. **Where the two disagree, the catalog trigger wins**,
because it is the wider one and a staleness signal is not something to resolve by picking the
narrower authority.

The requirement **binds on touch**, per the convention above: rows predating this rule keep their
citations as they are and adopt the record parts the next time they change. A missing stamp on an
older row is therefore not itself a defect in this catalog.

**Source lines name, never quote.** A row's Source line names the page and the section that
documents its mechanic; the firing rule above it is this catalog's decision, in its own words, and
works without a live fetch. Read the section's wording at the page.

**Admission.** A row's observable must be **anchored to text that is present**. A check detects a
passage a surface actually contains: either what it says, or an attribute it lacks while saying it.
I6 (a prohibition carrying no rationale marker) and I7 (a request stating no motivation) are the
anchored form: each names a line you can point at and judges what is missing *from that line*. What
is refused is the **unanchored** form, an obligation that a surface *should say* something, where
the finding points at no passage at all and the population is every file lacking the pattern. A
proposed Detect clause reading "a surface that does not …", with no passage to cite, is refused on
shape before its source is weighed, however well sourced. Such guidance routes to doctrine or to a mechanism instead, and an audit that
declines a row on this ground says where it routed, so "no row" never reads as "not covered".

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier**: `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified per Deletion tiers,
  never confident removals).
- **Authority**: `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice), or `HOUSE` (a session-knowledge defect this catalog defines
  itself; it has no external page to cite, and it is on by default because its ground truth is the
  surface's own text rather than a model-era claim). A closed four-value set.
- **Severity**: `error` / `warning` / `info`.

**Model scoping.** A check or row sourced from a SINGLE model's guide is annotated
`Model scope: <version>[, <version> ...]` and FIRES only when the run's resolved target
model (the skill body owns `--target-model` resolution) exactly matches one of the listed tokens;
otherwise it is inert and the report lists it as
`skipped-for-target`. **The match is exact string equality of the normalized version token**
(e.g. `opus-5`): a point release or a dated full model ID does NOT auto-match a base-version scope.
Model guides are calibrated per version, and successive guides have reversed each other, so a
near-miss target skips the row (reported `skipped-for-target`, naming the near-miss) rather than
inheriting a sibling version's doctrine. The scope value is data: no check body branches on a
model name in prose. Promotion to fleet-wide (unscoped) happens only through the gate: an
authoritative model-agnostic upstream doc states the claim, OR multiple model guides converge on
it. Unannotated checks are model-agnostic and always fire.

**Tokens of models that are no longer current.** A scope token stays while Claude Code can still
put a session on its model by fallback. On 2026-10-01 that held for `opus-5`, `opus-4-8` and
`sonnet-5`, so no row drops one. `fable-5` is not in this set: we treat Fable 5 as a current model,
since Claude Code still offers it for selection. Each row scoped to a token in this set, or to
`fable-5`, carries a "Re-justified" line saying why its scope neither drops nor widens to another
current model.

- **Pointer**: for the fallback targets, see
  [model configuration: automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback);
  for how Fable 5 is selected, see
  [model configuration: work with Fable](https://code.claude.com/docs/en/model-config#work-with-fable).
- **As of**: 2026-10-01
- **Recheck trigger**: a model leaves Claude Code's model page, which retires its token in every
  row that names it, or Fable 5 stops being selectable there.

**`OPINION` enablement.** Enablement attaches to *detection*, never to advice, and splits on what a
rule does:

- An `OPINION` check that **emits** findings is **off** on bare invocation, enabled only by the
  explicit `--opinion` argument, capped at `info`, and never fix-applied. An unconfirmed
  practitioner preference does not get to mutate a consumer's instruction corpus under the same
  banner as documented doctrine.
- An `OPINION` rule that **withholds** findings is **on** by default, disabled only by an explicit
  opt-out. Defaulting a suppressor off would not make the audit more conservative. It would delete
  the only bound on the checks it moderates.
- `OPINION`-derived *advice* inside a backed check's Remediate line follows that check's enablement
  and severity, because the detection is the host's and is backed. It is labeled inline as
  `OPINION`-derived and is never fix-applied.

Every run reports one line naming how many `OPINION`-tier checks were available, how many did not
run, and the argument that enables them, because an off-by-default tier nobody can find is shipped
in name only.

**Surface partition.** Checks I1–I5 are the instruction-memory hygiene layer: they apply on
non-memory surfaces (skill bodies, agent definitions, hook instruction text, output styles); on
memory-layer surfaces (CLAUDE.md, a natively read AGENTS.md, CLAUDE.local.md, `.claude/rules/`,
`~/.claude/rules/`) their findings route to the `harness-memory` plugin's `audit` skill when it is
installed, and fall back to the official include/exclude guidance (I1–I5 source below) when it is
not. Checks I6–I12, I16–I28, I30, and I35–I37 apply to all surfaces. I15 also applies to all
surfaces, but its unit is a pair, so Phase B2 answers it rather than a per-surface lane. I13, I14,
I29, I31, I32, I33, and I34 name narrower surface sets in their own rows, and a lane runs each only
on the surfaces its row names.

## Sources

- Claude Code best practices: <https://code.claude.com/docs/en/best-practices>
- Prompting best practices:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Prompting Claude Opus 5:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5>
- Prompting Claude Fable 5.1:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>.
  The `fable-5-1` widenings below rest on it, in place of the bundled `claude-api` skill's
  model-migration reference they first cited; that skill's record lives in
  [bundled-claude-api.md](bundled-claude-api.md).
- What's new in Claude Fable 5.1 (its refusal categories, for I10):
  <https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1>
- Prompting Claude Sonnet 5.5 (the `sonnet-5-5` rows and widenings below):
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>
- Prompting Claude Opus 5.5:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
- Getting the most out of Opus 5.5 in Claude and Claude Code (vendor blog, published 2026-09-22).
  Not a pointer (correlate only): the docs pointer is Prompting Claude Opus 5.5 above, and the
  citing rows keep that guide's `ANTHROPIC-DOCS` Authority;
  correlate with <https://claude.dev/blog/getting-the-most-out-of-opus-5-5/>
- Prompting Claude Sonnet 5:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5>
- Prompting Claude Opus 4.8:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8>
- The new rules of context engineering for Claude 5 generation models (vendor blog, published
  2026-07-24). Not a pointer (correlate only): the docs pointer is Prompting best practices above,
  for I6 and I15, whose rows keep the `ANTHROPIC-DOCS` Authority of their documentation sources, so
  the closed four-value Authority set above is unchanged;
  correlate with <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>
- Memory (CLAUDE.md, a natively read AGENTS.md, rules, auto memory):
  <https://code.claude.com/docs/en/memory>
- The `.claude` directory: <https://code.claude.com/docs/en/claude-directory>
- Skills (what loads when, how supporting files are referenced, the listing budget,
  invocation-control fields): <https://code.claude.com/docs/en/skills>
- How features layer (per-surface precedence, routing between surfaces):
  <https://code.claude.com/docs/en/features-overview>
- Context window (what survives compaction): <https://code.claude.com/docs/en/context-window>
- Hooks (handler types, and which events inject handler output into context):
  <https://code.claude.com/docs/en/hooks>
- Refusals and fallback (`reasoning_extraction`, and the classifier-category set it belongs to):
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- Introducing Claude Fable 5 and Claude Mythos 5 (which models carry the safety classifiers):
  <https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5>
- Thinking (the sanctioned reasoning-visibility path, the `display` field, the thinking-block
  round-trip protocol, the per-model table of accepted `thinking` values including `between_tools`,
  the models that reject a thinking-disable outright or non-default sampling parameters, and what a
  thinking or effort change does to the cache prefix):
  <https://platform.claude.com/docs/en/build-with-claude/thinking>
- Steering thinking (the turn-validation relaxation, and the models that still enforce a leading
  thinking block):
  <https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost>
- Troubleshooting thinking (the per-request 400s, the models the effort restriction covers, and the
  internal-tag leakage a don't-think directive worsens):
  <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
- Model migration guides. The migration-guide URL is an index of per-model guides
  (<https://platform.claude.com/docs/en/about-claude/models/migration-guide>); I25 cites the Fable
  and Mythos guide's section on migrating from Claude Opus 5:
  <https://platform.claude.com/docs/en/models/fable-5/migration-guide#migrating-to-claude-mythos-5-and-claude-fable-5-from-claude-opus-5>.
  The model ranges that reject manual extended thinking (I17-c) and non-default sampling
  parameters (I25) are read from Thinking, above.
- Claude Sonnet 5 model page, "Good to know" (the sampling-parameter constraint on the Sonnet class):
  <https://platform.claude.com/docs/en/models/sonnet-5/overview#good-to-know>
- Effort (the levels, `high`'s equivalence to omitting the parameter, the carry-over sweep advice,
  and where thinking may not be disabled):
  <https://platform.claude.com/docs/en/build-with-claude/effort>
- Model configuration (the harness-side thinking-display and thinking-disable surfaces, which effort
  levels each surface accepts, the per-model calibration of the effort scale, the first-run
  default hold, and the adaptive-reasoning / fixed-thinking-budget partition):
  <https://code.claude.com/docs/en/model-config>
- Settings (the `effortLevel` value set): <https://code.claude.com/docs/en/settings>
- Environment variables (`CLAUDE_CODE_EFFORT_LEVEL`, `MAX_THINKING_TOKENS`, and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` with the models it reaches):
  <https://code.claude.com/docs/en/env-vars>; read it whole per the
  [fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis-the-fetch-route),
  because a summarizing fetch truncates this page well before these rows
- Prompt caching (what belongs to the cache key): <https://code.claude.com/docs/en/prompt-caching>
- Errors (what Claude Code sends, or reports, when thinking is off at an effort level the model
  refuses with it): <https://code.claude.com/docs/en/errors>
- CLI reference (`claude doctor` and the other terminal forms):
  <https://code.claude.com/docs/en/cli-reference>
- Subagents (what loads into a subagent at startup): <https://code.claude.com/docs/en/sub-agents>

---

### Deletion tiers

Two deletion tiers, editorial and consequential, and one hold outside them, protected. One
grammar. The grammar is `unhobble`'s re-add gate: a ledger row, same-cause
aggregation, and a commit that cites the rows. This catalog does not define a second grammar.
The operational form is `/harness-config:unhobble watch`.

- **Editorial.** I1 (removal would not change behavior), I4 (derivable or redundant), and stale
  scaffolding that restates the obvious. Propose the cut. No watch.
- **Protected.** A candidate matching the instruction exception register. Hold. Never a watch
  and never a deletion. Compression in place or hook conversion stays available.
- **Consequential.** A rule that governs a situation and is outside the register. Do not present
  the deletion as applicable. Propose opening a watch for that rule. The cut becomes applicable
  only when a closed watch is cited: its qualifying-session count met and zero attributed rows.
  The recommended commit cites that watch. That citation is what clears this tier.

### I1: Line-necessity bar

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a line whose removal would not change behavior: it restates a default, a truism, or
  something the model already does correctly.
- **Remediate:** cut it. This check's cut is editorial (Deletion tiers) and does not require a
  watch. If the line enforces a governed situation, it is consequential: convert per I5 or open a
  watch, and do not cut it on this check alone.
- **Hold instead of delete** when the candidate matches a protected class in the
  [instruction exception register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md),
  on I5's terms. This bar asks whether removal would change behavior *today*; a protected rail's
  removal changes behavior only on the occasion it was written for, which this criterion cannot
  observe.
- **Source:** best-practices, "Write an effective CLAUDE.md" (the per-line removal test).

### I2: Length and skimmability

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a surface long or dense enough that its own rules start getting ignored; the tell is
  the model breaking a rule the file contains.
- **Remediate:** prune, split into path-scoped rules or skills, tighten structure.
- **Source:** best-practices, "Write an effective CLAUDE.md" (file length and ignored rules).

### I3: Broad-applicability placement

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** only-sometimes-relevant content (a workflow, domain knowledge, one subsystem's
  quirks) living in a surface that loads **more broadly than the content is relevant**. Two cases,
  because the surfaces this check runs on are not all always-loaded:
  - an always-loaded surface: the selected output style, an unscoped rule, root `CLAUDE.md` or a
    natively read root `AGENTS.md` where the partition allows it;
  - a surface loaded in full on every use of a component whose own scope is broader than the
    content's: a skill body or an agent definition covering several concerns, where the content
    matters to one of them and is in context for all of the others. Establish that breadth before
    flagging: a skill or agent that exists *only* for the content's concern loads it exactly when it
    is relevant, and is not a finding.
- **Remediate:** move it to a skill or a path-scoped rule that loads on demand. **A destination
  qualifies only if it defers loading.** `@path` imports do not, so a split into imports is an
  organizational change and not a context saving, and proposing one satisfies this check's letter
  while changing the load profile not at all. **State the move cost with the recommendation:** a
  `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file is
  read again, so content that must survive compaction stays unscoped or in the project-root
  `CLAUDE.md` (or the `AGENTS.md` read natively, whether in place of a `CLAUDE.md` or alongside
  one). **A *new* skill is not a free destination:** its body defers, but the listing entry it
  adds, `name` plus the combined `description` and `when_to_use` truncated at 1,536 characters, is
  always in context, so the saving is the body minus that entry rather than the whole body. Moving
  content into a skill that **already exists** adds no listing entry and does not carry this cost.
  The only field that keeps a description out of context is `disable-model-invocation: true`, which
  also makes the skill user-invocable only; `user-invocable: false` does not, and `skillOverrides`
  does not reach plugin skills at all. State the entry as a cost, not a threshold. Whether a corpus
  is over its listing budget is a different question and not this check's.
  **Content taken out of an agent definition needs an agent-reachable destination.** A subagent runs
  in its own context, inheriting no path-scoped rule and being told of none
  (<https://code.claude.com/docs/en/sub-agents>), so such a rule reaches a dispatch only if that
  dispatch happens to read a path its glob covers. Proposing one for instructions the agent needs
  trades guaranteed presence for a deferral the agent cannot rely on. Name a destination the agent itself
  reaches, meaning a skill the agent's definition **invokes at runtime** or text kept in the
  definition, and never a `paths:`-scoped rule. **A `skills:` preload is not such a destination**:
  we treat every preloaded skill's whole body as loaded into each dispatch of that agent, so the
  content is resident for every unrelated use exactly as it was in the definition, and the move
  defers nothing. That is the same disqualification `@path` imports carry above. When the agent has
  no conditional runtime invocation to move the content to, report that no safe deferral is
  available rather than proposing a preload that satisfies this check's letter and changes the load
  profile not at all.
- **Adjacent axis:** this check is load *timing*. Definition-site *locality*, an instruction sitting
  away from the thing it governs, is I16, and an instruction can be correctly deferred here and
  still misplaced there.
- **Source:** best-practices, "Write an effective CLAUDE.md" (broad applicability, skills for
  sometimes-relevant content); memory, "Import additional files" (imports load at launch);
  context-window, "What survives compaction", for the per-destination cost; skills, "Frontmatter
  reference" (description loading, the listing truncation this check keeps as its own 1,536
  setting, and the invocation-control fields) and "Override skill visibility from settings"
  (`skillOverrides` and plugin skills); subagents, the `skills:` field (preloaded skill content).
  Pointer: <https://code.claude.com/docs/en/skills#frontmatter-reference>,
  <https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings> and
  <https://code.claude.com/docs/en/sub-agents>. As of: 2026-08-31. Recheck trigger: either page
  changes the listing cap, which field keeps a description out of context, whether
  `skillOverrides` reaches plugin skills, or what a `skills:` preload injects; that re-derives
  this check's Remediate mechanics.

### I4: Inferable or redundant content

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** content the model can derive from the code, standard language conventions it already
  knows, inlined API docs that should be a link, or self-evident practices.
- **Remediate:** delete; link to the source of truth instead of inlining it. This cut is
  editorial (Deletion tiers) unless the line governs a situation, in which case it is
  consequential and needs a closed watch before the deletion is applicable.
- **Hold instead of delete** when the candidate matches a protected class in the
  [instruction exception register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md)
  (the Gate 0 consequence classes, adopted there by reference for the deletion operation). Report
  the hold and its class; propose compression in place instead. The register is non-exhaustive, so
  a candidate absent from it is judged on this criterion's normal terms, never deleted *because* it
  is absent.
- **Source:** best-practices, "Write an effective CLAUDE.md", the include/exclude table (its exclude
  column).

### I5: Rule-to-hook or delete

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: I1–I5 partition.

- **Detect:** a rule the model already follows without it, or one that must fire every time with
  zero exceptions.
- **Remediate:** an already-followed rule that does not govern a situation is an editorial
  deletion. A rule that governs a situation is consequential: open a watch, and propose the
  deletion only when a closed watch is cited (Deletion tiers). Convert a must-always rule to a
  hook either way; conversion is not a deletion.
- **Hold instead of delete** when the candidate matches a protected class in the
  [instruction exception register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md).
  "The model already does this" is the weakest possible evidence against a rail whose absence is
  unrecoverable, and the hook conversion stays available: converting a protected rule to a
  deterministic mechanism is a remediation, deleting it is not.
- **Source:** best-practices, "Avoid common failure patterns" (already-followed rules) and "Set up
  hooks".

### I6: Bare prohibition to positive reframing

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** a bare "never / do not / don't" instruction. The deterministic pre-scan seeds a
  sentence that opens with the prohibition and carries neither a paired positive ("instead",
  "rather than", "prefer", "in place of") nor a rationale marker, joining soft-wrapped paragraph
  lines into one sentence and never reading frontmatter, fenced code, table rows, or headings.
  Those exclusions are structural, not this row's fences: a prohibition the seed skips is still
  in scope when the lane reads it, and the report states the raw and surviving seed counts.
- **Remediate:** reframe positively, stating what to do instead, as the primary fix. Where a
  genuine hard "never" survives, keep it but add its rationale (see I7) as the fallback.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** prompting best-practices, "Control the format of responses" (positive framing).
  Corroborated from the model-delta side (correlate with the context-engineering blog under
  Sources, its "Then and now" section, whose worked example is an instance of this row's
  remediation shape).

### I7: Reason with the request

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all. Unscoped.
Promotion gate MET: the model-agnostic best-practices page states the same claim (see Source),
so this fires for every target model.

- **Detect:** an instruction that states a request with no intent or motivation attached.
- **Remediate:** add the why: the model connects the task to relevant context instead of inferring
  intent on its own.
- **Source:** Fable 5 guide, "Give the reason, not only the request". Convergent model-agnostic
  source (the gate-meeting one): Prompting best practices, "Add context to improve performance".

### I8: Model-era re-audit

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

Rows I8-a, I8-c, I8-d and I8-f carry their own `Model scope` (single-model guide sources; promotion
gate unmet). The base row and rows I8-b and I8-e are unscoped, since a model-agnostic statement or
convergent model guides meet the gate for each (see the rows); the base row's delegation-throttle
worked instance keeps a `fable-5` scope of its own.

**Base row** · Unscoped. Promotion gate MET on 2026-08-08: the model-agnostic best-practices page
states the claim under its all-current-models framing (section "Leverage thinking & interleaved
thinking capabilities", on general instructions over prescriptive steps). **The worked instance
below keeps a `fable-5` scope of its own**, because its basis is Fable-specific and the Opus guides
disagree with it.

- **Detect:** prior-model workarounds and over-prescriptive step lists: instructions enumerating
  behaviors a current model handles from a brief instruction, or scaffolding that pins an approach.
  **One named worked instance, offered for recognition rather than as a separate rule, and fired
  only on a `fable-5` or `fable-5-1` resolved target: a delegation throttle**, meaning a cap on
  concurrent workers, a one-at-a-time rule, or an instruction to block until each subagent returns
  before dispatching the next, where the surface's own ground for it is that subagent handling is
  unreliable. On a Fable target we treat a throttle resting on that premise as the generic case
  with a name on it. The Fable 5 guide ("Parallel subagents") and the Opus 5 and Opus 4.8 guides
  ("Controlling subagent spawning") disagree on throttling subagent dispatch, so on `opus-5` and
  `opus-4-8` targets this instance is inert, not merely unattested: there we treat a throttle as
  the recommended shape rather than a workaround. **A cap carrying its own
  non-model rationale is not this instance.** Reviewability of returns, rate limits, cost, or
  shared mutable state each justify a bound on their own terms, and that justification is the
  surface's to make, not this row's to override.
- **Remediate:** propose removal or a briefer instruction; verify per Deletion tiers (a
  consequential removal needs a closed watch, an editorial one does not) that default performance
  holds or improves.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** prompting best practices, "Leverage thinking & interleaved thinking capabilities"
  (the gate-meeting, model-agnostic one). Convergent model guide: Fable 5, "Recommended
  scaffolding changes" (prior-model skills as too prescriptive). The worked instance's basis is
  the same guide, "Parallel subagents"; its Opus counter-basis is the Opus 5 guide's and the Opus
  4.8 guide's "Controlling subagent spawning".
- **The general principle, and why it is cited separately.** The migration-framed sources above
  point a reader at what looks like leftover prior-model scaffolding, walking straight past
  freshly authored over-enumeration, which is the same defect with no legacy provenance to
  recognize it by. The Fable 5 guide's "Strong instruction following" states the principle on its
  own (a brief instruction in place of an enumeration), and that section's worked case is a *newly
  written* instruction, not a migration. **Age is not an element of this row.** Detect
  over-enumeration wherever it was written and whenever.

**Row I8-a: instructed self-check removal** · Tier `behavioral` · Model scope: `opus-5`.

- **Detect:** instructions telling the model to re-check work it already checks. The pre-scan's
  stems are `double-check`, `re-verify`, `final verification step`, and `subagent to verify`. Older
  harness text that bolts an extra checking pass onto every task counts too.
- **Classify by reviewer INDEPENDENCE, not invocation source:** architected independent review,
  meaning a fresh-context reviewer blind to the producing rationale or a different-vendor verifier,
  is NOT a finding; the anti-pattern is the instructed self-check. **Carve-out lanes (never
  flagged):** security review, destructive operations, managed-upstream-file changes, PR merge
  gates.
- **Remediate:** propose removal; verify per Deletion tiers (a consequential removal needs a closed
  watch, an editorial one does not).
- **Bounded by:** the **Stopping condition** below.
- **Source:** Opus 5 guide, "Task scope and over-verification" and "Self-correction".
- **The independence carve-out is corroborated by a second guide, and the scope does not move.** The
  Fable 5 guide's "Recommended scaffolding changes" section reaches the same line from the opposite
  direction, on making verification explicit on long runs with fresh-context verifiers. Read
  without that section, the two guides look contradictory, remove verification instructions versus
  add them, and a reader has to resolve it alone. We read them as consistent: the anti-pattern is
  the instructed **self**-check, and an architected independent verifier is what the Fable 5
  section covers. **This does not meet the promotion gate**, because the gate wants a second guide
  stating this row's *detection* claim, that verification instructions cause over-verification,
  and the Fable 5 guide states no such thing. The scope annotation stands; only the carve-out gains
  a second source.
- **Re-justified 2026-10-01 against the current models:** the scope stays `opus-5` (see "Tokens of
  models that are no longer current"). Our probe of the Fable 5.1, Opus 5.5 and Sonnet 5.5 guides
  that day (each read whole as raw markdown; no artifact stored) found no statement of the
  detection claim. We do not widen to `sonnet-5-5`: a finding there would remove the check the
  posture catalog's P13 asks a code-changing component to carry, and P13 cites this section.
  Pointer: [Sonnet 5.5 guide, verification on coding
  tasks](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#verification-on-coding-tasks);
  the probe covered the whole of [Prompting Claude Fable
  5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)
  and [Prompting Claude Opus
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5),
  so it names no section. As of: 2026-10-01. Recheck trigger: a current model's guide stating that
  verification instructions cause over-verification.

**Row I8-b: conservative-reporting detection** · Tier `behavioral`. Unscoped. Promotion gate MET
on its second arm: a second model guide, the Sonnet 5 one, states the same claim about the shared
trigger phrases (two of the three; see Source for the third's provenance), so this fires for every
target model.

- **Detect:** review/report instructions that gate severity at the FINDING stage, such as "be
  conservative," "only report high-severity issues," and "don't nitpick", which current models
  follow literally, withholding real findings. The gate is about WITHHOLDING findings from the
  audit or report output: severity-based routing where everything is still reported somewhere
  ("only page on-call for high-severity; log the rest") and non-reporting uses of "conservative"
  ("conservative time estimates") are not findings.
- **Two fences, OWNED HERE (the scanner over-produces by contract; the model lane adjudicates):**
  1. **Restraint-clause shape**: a clause bounding when a TRANSFORMATION or action applies
     ("When NOT to apply…", "skip the change when…") is not a reporting gate; the canonical
     non-finding shape is a tidying catalog's restraint text (in this monorepo, the catalog
     `/code-tidying:tidy` loads; in a standalone install the shape, not the path, is the fence).
  2. **Quoted/meta surfaces**: a document that DISCUSSES the conservative-reporting pattern
     (this criteria file, a model-adaptation delta chapter, verification records quoting it) is
     not a finding. Judge at the level of the instruction's audience: quoted text embedded inside
     an operative directive ("follow the maxim: 'only report high-severity issues'") is still
     operative and IS a finding; the exemption is for documents about the pattern, never for
     quotation as packaging.
- **Remediate:** rephrase to report-everything + a separate filter/rank pass. Where a single-pass
  self-filter is genuinely wanted, keep it but **state the bar concretely**, as an enumerable test
  the reader can decide a novel finding against, rather than a qualitative term.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** the gate rests on two model guides that name the trigger phrases: the Opus 5 guide
  for the first two and the report-everything-then-filter remediation, and the Sonnet 5 guide for
  all three and the Remediate line's concrete-bar half. The Opus 4.8 guide corroborates the third
  phrase, "don't nitpick"; the gate was met without it. The Opus 5 guide does not use that phrase.
  Pointer: [Opus 5 guide, capability
  improvements](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#capability-improvements)
  (its code review and bug-finding item), [Sonnet 5 guide, code review
  harnesses](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#code-review-harnesses)
  and [Opus 4.8 guide, code review
  harnesses](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8#code-review-harnesses).
  As of: 2026-08-08 (our probes, no artifact stored: the Opus 4.8 guide's raw `.md`, 15,905 bytes,
  MD5 `6b9db5b784ad6a7b2e6307c1481b8be9`; the Opus 5 guide's raw `.md`, zero occurrences of
  "nitpick"). Recheck trigger: either gate guide drops the trigger phrases from its section, or
  the Opus 5 guide starts using "nitpick".

**Row I8-c: don't-think / don't-reason directive** · Tier `behavioral` · Model scope: `opus-5`,
`opus-5-5`, `sonnet-5-5`.
**The scope is positively confirmed narrow rather than merely unsourced.** A second page states the
claim (see Source), and it is a model-agnostic feature page, the surface where a wider claim would
appear, yet it names Claude Opus 5 anyway. The promotion gate stays unmet by upstream's own
choice, on the same reasoning I10 applies to a declined widening.

- **Detect:** a directive forbidding the model to think or reason. We treat such a directive as
  making internal-tag leakage worse when thinking is off. Also flag tag-hygiene rules that name
  thinking tags specifically (less effective than the general form).
- **Where it shows, and why it outlives the turn.** We look first at a surface governing a
  tool-driven lane, such as search, since the troubleshooting page places the leakage on tool-heavy
  workloads, and we treat the damage as not confined to the response that leaks: a tool call
  emitted as text is never executed, and that text remains in the loop's history afterwards. The
  page states the history effect, not this consequence. Read here, that means an autonomous lane
  carries the poisoned turn forward as context.
- **Remediate:** remove the directive; where output-tag hygiene is genuinely needed, use the
  general "internal or system XML tags" phrasing.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5 guide, "Running with thinking disabled" (the removal, and the general form over
  naming thinking tags). Corroborated at troubleshooting thinking, "Tool calls or XML tags appear in
  the text output", which reaches the same claim from the symptom side and is the source of the
  condition and consequence above. **As of 2026-08-04** (that page read as raw markdown).
  **Recheck trigger:** a second model name appearing beside Claude Opus 5 in either section that
  states the claim: the Opus 5 guide's "Running with thinking disabled", or this page's "Tool
  calls or XML tags appear in the text output". A new name re-opens the scoping question, not the
  gate itself: the added model joins as a named Detect condition, and unscoping still requires
  what the gate has always required, an unqualified model-agnostic statement or convergent model
  guides, since a claim qualified to two models licenses nothing about the rest. Neither page
  enumerates the models that do *not* leak, so those two sections are the whole of what there is
  to re-read.
- **Widened to `opus-5-5` on 2026-09-23:** the Opus 5.5 guide, "Prompts written for thinking
  disabled", prescribes removing the no-thinking rule on that model, where thinking is always on.
  On `opus-5-5` the Detect clause's leakage premise does not apply; the finding stands on that
  removal alone. **As of 2026-10-02**, moved (our probe: the guide's raw `.md`, 28,499 bytes, MD5
  `5278fe0b08f0532c308dad50efa0f153`). **Recheck trigger:** that section ceasing to prescribe the
  removal.
- **Considered for `sonnet-5-5` on 2026-10-01 and declined.** We read the Sonnet 5.5 guide as
  covering this directive only under the `between_tools` thinking setting (pointer below), and no
  Claude Code surface exposes that setting, so a session reading a Claude Code surface never runs
  under it. On a `sonnet-5-5` target the row stays inert. Ownership of `between_tools` text is
  split once, the same way in this row and in I17's third arm: a prompt in application source that
  sends `between_tools` is the bundled `claude-api` skill's (SKILL.md, "Boundary"); instruction
  text that prescribes a `between_tools` request is in this catalog only through I17's third arm,
  which flags the refused pairings and not this directive.
  Pointer: [Sonnet 5.5 guide, running without up-front
  thinking](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#running-without-up-front-thinking).
  For the Claude Code negative, our probe read [model
  configuration](https://code.claude.com/docs/en/model-config),
  [settings](https://code.claude.com/docs/en/settings), [settings
  reference](https://code.claude.com/docs/en/settings-reference) and [environment
  variables](https://code.claude.com/docs/en/env-vars#variables) whole as raw markdown and found
  no control for that setting (no artifact stored). As of: 2026-10-01. Recheck trigger: Claude
  Code gains a `between_tools` control, or the Sonnet 5.5 guide states the claim outside
  `between_tools`.
- **Re-justified 2026-10-01 against the current models:** `opus-5` stays (see "Tokens of models
  that are no longer current"), and both sections the trigger above watches still name Claude Opus
  5 alone. Pointer: [Opus 5 guide, running with thinking
  disabled](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#running-with-thinking-disabled)
  and [troubleshooting thinking: tool calls or XML tags appear in the text
  output](https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting#tool-calls-or-xml-in-text)
  (the rendered page gives this heading the id `tool-calls-or-xml-in-text`). As of: 2026-10-01.
  Recheck trigger: the same as this row's trigger above.

**Row I8-d: short-turn assumptions** · Tier `behavioral` · Model scope: `fable-5, fable-5-1`.

- **Detect:** instruction text resting on the premise that a turn is short: a directive to answer
  quickly or keep turns brief, or any required progress rhythm pinned to a turn rather than to the
  work. We treat a single high-effort request as lasting minutes and an autonomous run as lasting
  hours, so a rhythm calibrated to the old turn length fires as noise on work that has not reached a
  reportable boundary, and it interrupts precisely the long uninterrupted runs the model is being
  used for.
- **The forced interim-status cadence shape is owned fleet-wide by I8-e**, which is unscoped since
  its promotion gate met (see that row) and rests on two guides' directly stated claim rather than
  on this row's duration premise. To keep one finding per line, a cadence instruction reports as
  I8-e on every target; this row keeps the remaining short-turn shapes: the answer-quickly
  directive, and a non-status rhythm pinned to a turn rather than to the work.
- **Remediate:** name the constraint the brevity or rhythm was protecting, whether a latency
  requirement, an external contract, or a human process, and where one exists, state that
  constraint instead of the turn-length assumption; where none exists, remove the directive and let
  turn length follow the work. Verify per Deletion tiers (a consequential removal needs a closed
  watch, an editorial one does not).
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Must NOT flag: an output-length instruction.** Brevity of the *reply* is a different subject and
  belongs to I8 base; this row's subject is the cadence and duration of the *turn*.
- **Must NOT flag: a latency or duration requirement the surface genuinely owns**: a product SLA, a
  timeout a downstream contract imposes, a rhythm a human review process depends on. Those are
  constraints the surface is entitled to state, not assumptions about how long a model takes.
- **Must NOT flag: a document *about* the pattern**, such as this row, a model-adaptation delta
  chapter counter-steering it for a different model, or a verification record quoting it, on the
  same audience test I8-b applies.
- **Scope, and what is deliberately outside it:** the guide pairs this behavior with advice to adjust
  **client timeouts, streaming, and progress indicators** before migrating. That half is harness
  client configuration rather than instruction content, so it is not audited here and no row claims
  it; a surface whose *instruction text* prescribes a short client timeout is the shape that would
  reach this catalog, and none is attested.
- **Source:** Fable 5 guide, "Longer turns by default".
- **Widened to `fable-5-1` on 2026-09-03**, first on the bundled `claude-api` skill's
  model-migration reference. That basis's trigger fired when the Fable 5.1 guide was published. The
  widening now rests on our rule that a Fable 5 row applies to Fable 5.1 unless the Fable 5.1 guide
  names a difference on the row's subject, and on our reading of that guide on 2026-10-01 (read
  whole as raw markdown; no artifact stored): no section names a turn-length difference. Pointer:
  [Prompting Claude Fable
  5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1),
  the text above its first heading, which carries no heading id on the rendered page, so the link
  is to the page. As of: 2026-10-01. Recheck trigger: the Fable 5.1 guide naming a turn-length
  difference from Fable 5, or its opening changing what it says about Fable 5 prompts.
- **Re-justified 2026-10-01 against the current models:** `fable-5` stays, since Fable 5 is a
  current model (see "Tokens of models that are no longer current"). Our probe of the Opus 5.5 and
  Sonnet 5.5 guides that day (each
  read whole as raw markdown; no artifact stored) found no statement of the short-turn claim, so
  the row does not widen to them. Pointer: [Prompting Claude Opus
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
  and [Prompting Claude Sonnet
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5),
  whole pages, since the probe is a negative over every section. As of: 2026-10-01. Recheck
  trigger: either guide gains a section on turn length.

**Row I8-e: forced interim-status cadence** · Tier `behavioral`. Unscoped. Promotion gate MET:
two model guides state the claim (see Source).

Unscoped: two model guides state the claim (see Source), which meets the promotion gate. The Fable
5 guide's verified negative below is a reading of that guide, and the scope does not rest on it.
**This row owns the cadence shape on every target**; I8-d cedes it (see that row) so the two
report one finding per line rather than two.

- **Detect:** an instruction requiring interim status output on a fixed mechanical interval, such
  as a summary after every few tool calls, "check in after each file", or "post an update every N
  minutes". The subject is the *forced rhythm*, not the reporting: an instruction to report
  at a genuine work boundary (a phase completing, a gate failing) pins to the work and is not a
  finding.
- **Remediate:** name the guarantee the cadence was protecting, that the user can see progress or
  that a long run stays interruptible, and either state that outcome and let the model meet it, or
  move it to a mechanism rather than an instructed rhythm. Where the *content* of native updates is
  miscalibrated rather than absent, describe what a good update contains and give examples; that
  remediation comes from the Sonnet 5 guide and does not reintroduce a cadence. Verify per
  Deletion tiers (a
  consequential removal needs a closed watch, an editorial one does not).
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Must NOT flag: a cadence carrying its own explicit observability or interruptibility
  rationale.** A rhythm the surface states exists so a long autonomous run stays visible or
  interruptible names the very guarantee the Remediate line protects, and that design is the
  surface's to make, unless evidence shows the cadence was calibrated to an obsolete turn length
  rather than to the work.
- **Must NOT flag: a latency or duration requirement the surface genuinely owns**: a rhythm a human
  review process depends on, a heartbeat an external contract requires. Those are constraints the
  surface is entitled to state, on the same reasoning I8-d applies to its own.
- **Must NOT flag: a document *about* the pattern**, such as this row, a model-adaptation delta
  chapter counter-steering it, or a verification record quoting it, on the same audience test I8-b
  applies. This catalog's own detect text is the canonical instance; the deterministic pre-scan
  seeds no pattern for this row, so it carries no fixtures of its own.
- **Source:** Sonnet 5 guide, "User-facing progress updates" (removing forced status scaffolding,
  and the Remediate line's second half). Convergent second model guide (the gate-meeting one): Opus
  4.8 guide, "User-facing progress updates".
- **As of 2026-08-08** (our probe of both gate sources as raw markdown: the Sonnet 5 guide, 15,864
  bytes, MD5 `6d23959f0ed226feb06bf20c314029e3`, byte-identical to 2026-07-29 and 2026-08-04
  captures; the Opus 4.8 guide, 15,905 bytes, MD5 `6b9db5b784ad6a7b2e6307c1481b8be9`). The
  2026-08-04 **verified negative** on the Fable 5 guide was re-checked 2026-08-08 against that
  guide's raw `.md` and is retained as our reading of that guide, on which the scope does not rest:
  no section of it prescribes removing instructed status cadence ("Longer turns by default" covers
  client-side adjustments only, and "Create a send-to-user tool" points the other way). **Recheck
  trigger:** either gate source ceasing to prescribe removal of forced status scaffolding, which
  re-opens the scoping question.

**Row I8-f: think-carefully steer** · Tier `behavioral` · Model scope: `opus-5-5`. **The gate is
unmet by contradiction, not only by absence:** the base row's model-agnostic source favors a
general think-thoroughly prompt over a hand-written plan, so an unscoped row would contradict it.

- **Detect:** a standing instruction telling the model to think carefully, hard, deeply, or step by
  step before answering, or an `ultrathink`-style keyword written into a saved instruction rather
  than typed for one piece of work. We treat the line as adding latency without a clear quality
  gain on Opus 5.5, where thinking is always on and the model sets its own depth.
- **Remediate:** delete the line. Where the intent was more or less depth, change effort, the
  documented control; where a fast answer to simple questions was the intent, lower effort first,
  and add an "Answer directly." line only after measuring quality with it, since less thinking can
  lower quality.
- **Must NOT flag:** "step-by-step" describing a procedure the text lays out, or instructions for a
  human reader; a per-invocation keyword the human types (I21 owns effort pinning); a document
  *about* the pattern, on the audience test I8-b applies.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5.5 guide, "Thinking instructions in chat system prompts" (the removal and its
  effect); "Calibrate effort" for the lower-effort-first remediation. The guide scopes the claim to
  chat system prompts; we apply it to saved Claude Code instructions as well, with effort as the
  Claude Code control (correlate with the vendor usage guide under Sources). **As of 2026-09-23**
  (our probe: the guide's raw `.md`, hash as in I8-c). **Recheck trigger:** a second model
  guide stating the claim, which re-opens the scoping question, or the section dropping it.
- **Cross-reference, Sonnet 5.5.** The row stays scoped to `opus-5-5` and is inert on a
  `sonnet-5-5` target. Its firing set on an `opus-5-5` target is unchanged: a surface that also
  serves Sonnet 5.5 is still flagged. When the flagged line asks for reasoning on a task answered in
  JSON, the finding adds that the line may be serving Sonnet 5.5, and proposes splitting it per
  model rather than deleting it; for that model's position, follow the pointer.
  Pointer: [Sonnet 5.5
  guide, reasoning tasks with JSON
  output](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#reasoning-tasks-with-json-output).
  As of: 2026-10-01. Recheck trigger: either guide changes its position on thinking instructions.

### I9: Example hygiene

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an example block that pins the model's *approach* to a task (behavioral scaffolding).
  Do not flag examples that steer output format, tone, or structure. Those remain recommended.
- **Remediate:** keep 3–5 diverse format/tone/structure examples; propose trimming or reframing
  only approach-pinning ones, A/B'd against the no-example default. Where the example block exists
  to enumerate what a caller may pass, such as modes, options, or permitted values, name the interface
  destination that carries it instead: an argument enumeration, a frontmatter field, a typed
  `argument-hint`. That destination clause is **`OPINION`-derived**, since no official page states
  it, so it rides this check's enablement and severity per the `OPINION` policy above, is labeled
  as `OPINION` in the finding, and is never fix-applied.
- **Source:** prompting best-practices, "Use examples effectively" (examples as format, tone and
  structure steering, and diversity against unintended patterns).

### I10: Reasoning-echo directives

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all · Model scope:
`fable-5, fable-5-1, opus-5-5, sonnet-5-5` (the cited refusal category is documented per model;
promotion gate unmet, see "Unscoping considered" below).

- **Detect:** instructions asking the model to put its internal reasoning into the reply itself,
  whether by showing, repeating, writing out, or narrating it. The deterministic pre-scan marks
  show-your-thinking phrasing.
- **Remediate:** remove them; where reasoning visibility is genuinely needed, read structured
  `thinking` blocks through the surface that already exposes them: in Claude Code, `Ctrl+O` verbose
  mode and the `showThinkingSummaries: true` setting (model configuration); on the API,
  `display: "summarized"` (Thinking). A send-to-user tool remains the path when the reasoning has to
  reach the user as ordinary response text.
- **Source:** Fable 5 guide, "Recommended scaffolding changes" (the `reasoning_extraction` refusal
  category on Claude Fable 5). Corroborated by the Thinking page, which documents the same refusal
  category for the same model. That second citation does **not** move the promotion gate: its own
  section names both Claude Fable 5 and Claude Mythos 5 for the adjacent raw-chain-of-thought
  property, then names Fable 5 alone for the refusal. That is a sentence-adjacent chance to widen,
  declined, so the narrower scope is deliberate.

  **`Model scope: fable-5` is positively sourced**,
  in two statements each taken from the page that owns its half. The page that owns Mythos 5 scopes
  the whole classifier set to Claude Fable 5 and excludes Claude Mythos 5 ([Introducing Claude
  Fable 5 and Claude Mythos
  5](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5),
  read 2026-08-03). Refusals and fallback places this row's category inside that set, listing
  `reasoning_extraction` among the classifier categories a refusal reports. Which
  models carry the classifier set is a per-model fact and moves, so the introducing page joins
  `## Sources`: the catalog-wide trigger then fires this row whenever that page changes, and no
  narrower per-row trigger is owed.

- **Widened to `fable-5-1` on 2026-09-03**, first on the bundled `claude-api` skill's
  model-migration reference. That basis's trigger fired when the Fable 5.1 guide was published.
  The widening now rests on the refusals section of Fable 5.1's own model page. Pointer: [What's
  new in Claude Fable 5.1, refusals, fallback, and
  billing](https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1#refusals-fallback-and-billing).
  As of: 2026-10-01. Recheck trigger: that section stops covering the `reasoning_extraction`
  category for Fable 5.1.
- **Widened to `opus-5-5` on 2026-09-23:** the Opus 5.5 guide, "Safeguard refusals", documents the
  `reasoning_extraction` category for that model, and how server-side fallback handles those
  declines. Remediate there as above, or ask for what the reader needs instead, such as the
  rationale in a few sentences. **As of 2026-09-23** (our probe: the guide's raw `.md`, hash as in
  I8-c). **Recheck trigger:** that section dropping the category.
- **Widened to `sonnet-5-5` on 2026-10-01.** On a `sonnet-5-5` target, fire on the same Detect and
  remediate as above. Pointer: [Sonnet 5.5 guide, safeguard
  refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#safeguard-refusals).
  As of: 2026-10-01. Recheck trigger: that section drops the `reasoning_extraction` category.
- **Unscoping considered on 2026-10-01 and declined.** Four model guides now name the category
  (Sonnet 5.5, Opus 5.5, Fable 5.1 and Fable 5), which on its face meets the convergent-guides arm
  of the promotion gate. We keep the row scoped because we read the category as a per-model
  classifier, not a behavior every model shares, so an unscoped row would flag text on targets
  where the line draws no refusal. Pointer: the four places that name the category, [Sonnet 5.5
  guide, safeguard
  refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#safeguard-refusals),
  [Opus 5.5 guide, safeguard
  refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#safeguard-refusals),
  [Prompting Claude Fable
  5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)
  (the note above its first heading, which carries no heading id on the rendered page, so the link
  is to the page) and [Fable 5 guide, recommended scaffolding
  changes](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#recommended-scaffolding-changes);
  for the categories themselves, see [refusals and fallback: refusal
  response](https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback#refusal-response).
  As of: 2026-10-01. Recheck trigger: a model-agnostic page stating that every current model
  declines reasoning extraction.
- **Re-justified 2026-10-01 against the current models:** `fable-5` stays, since Fable 5 is a
  current model (see "Tokens of models that are no longer current").

### I11: CLI over MCP where equivalent

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an instruction steering the model to an MCP tool where an equivalent CLI exists, when
  the surface's concern is context cost rather than a capability the MCP server uniquely provides.
- **Remediate:** prefer the CLI for the equivalent operation; keep the MCP path where it adds
  capability.
- **Source:** best-practices, "Use CLI tools" (context efficiency).

### I12: Stale or misattributed harness-capability claim

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** an instruction that asserts a Claude Code *harness* behavior, such as what a command
  does, what a keystroke saves, what loads into which context window, or what a mode persists, where
  **either** the official documentation **for the version the claim is about** states something
  incompatible with it, **or** a reproduction matching **every** stated precondition fails. The
  subject is the product, not the model, which is what separates this from I8.
- **Remediate:** correct the claim against the cited page, or cut it and point at the page instead
  of restating it. Where the behavior is version-gated, carry the minimum version with the claim.
- **Must NOT flag: silence.** A page that no longer mentions a behavior is not evidence the behavior
  changed. Product documentation is routinely rewritten, condensed, or reorganized, and this
  repository deliberately keeps empirical smoke tests for behaviors the official pages never
  specified at all. Absence of documentation raises the claim for reproduction; it does not
  establish drift, and it never on its own justifies a removal.
- **Must NOT flag: a gated claim that still reproduces under its own conditions.** Match the
  conditions before matching the text. Version is the common one, since a claim scoped to a pinned
  or supported older release is measured against that release, not against the latest page, but it
  is not the only one: **OS, a setting, an account tier, a feature flag, and launch mode are equally
  preconditions**, and a replay under different conditions proves nothing about the instruction.
  **A successful matched reproduction settles it**; a failed one settles it only when every stated
  precondition was met, and is otherwise **inconclusive rather than a finding**. A claim carrying no
  conditions is about current default behavior and is measured against the current page. This is the
  mirror of the remediation above: a catalog that asks authors to carry a claim's conditions must not
  then flag the claims that do.
- **Must NOT flag:** prose that names two adjacent forms and distinguishes them correctly. The
  terminal `claude doctor` being read-only while the in-session `/doctor` applies fixes is the
  canonical pair, and a file that states both is right, not drifting. A bare routing pointer that
  tells the reader to run a command without claiming what it does. Text that quotes a retired
  affordance explicitly as retired.
- **Must NOT flag: a claim about the content of the operator's own config files**, such as what
  their `settings.json` chains or which hooks they wire. That describes a file, not the harness, so
  it is not a harness-behavior claim. When the evidence in hand shows it false, report it under
  [Out-of-catalog defects](#out-of-catalog-defects).
- **Source:** CLI reference, "CLI commands", the `claude doctor` row (terminal diagnostics versus
  the in-session `/doctor`).

### I13: Citation form that does not load

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: non-memory only
(skill bodies and their reference files, agent definitions, hook instruction text, output styles).

- **Detect:** an `@path` written outside backticks and outside a fenced block on a surface where `@`
  carries no import meaning, **in prose that asserts the file has already arrived**: "as specified
  in @reference/rules.md above", "the criteria in @reference/criteria.md are loaded", a claim that
  the content is present rather than an instruction to go get it. Import syntax is a property of the
  CLAUDE.md family; on a skill or agent surface the `@` is inert, so an instruction written on the
  assumption that it imported is describing a load that did not happen.
- **Remediate:** rewrite the assertion into an explicit read, and cite the file the way that surface
  actually resolves, a backticked path or a markdown link. **Changing the citation syntax alone is
  not the fix**: neither form imports anything either, so a diff that swaps `@reference/rules.md` for
  a backticked path while leaving "as specified above" in place keeps the false claim and still lets
  the agent proceed without the content. The false premise is the defect; the syntax is where it
  shows.
- **Must NOT flag: an `@path` the surrounding prose treats as a file to read.** The path is still
  legible in the loaded prompt, so "follow `@reference/rules.md`" works: the reader opens it, and
  the inert prefix costs one character. **The finding is the false assumption of automatic loading, not
  the citation form**, and a warning on every inert `@` would flag working instructions. When the
  prose does not say the content already arrived, leave it.
- **Must NOT flag:** anything on a memory-layer surface, where `@path` genuinely imports. A
  package scope (`@anthropic-ai/…`), a decorator, an email address, or a `@username` handle. A
  backticked `` `@path` ``, which the import parser skips by design and which is the documented
  way to mention a path without importing it. A path cited without an `@` at all.
- **Source:** memory, "Import additional files" (import syntax on the CLAUDE.md family), against
  skills, "Add supporting files", where supporting files are referenced for Claude to load when
  needed and no import syntax is defined.

### I14: Retrieval of an already-loaded surface

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: agent definitions and
skill bodies.

- **Detect:** an instruction directing the agent to go read a surface the main conversation loads at
  startup and therefore already carries: the **root** project `CLAUDE.md` in **either** supported
  location (`./CLAUDE.md` **or** `./.claude/CLAUDE.md`), the user `CLAUDE.md` at the **resolved**
  `${CLAUDE_CONFIG_DIR:-~/.claude}`, the **root** `CLAUDE.local.md`, the **root** `AGENTS.md` or
  `./.claude/AGENTS.md` where the session reads it natively, unconditional
  project rules (no `paths` frontmatter), and managed policy files. Each of the three qualifiers is
  required.
  Root-level: the startup guarantee is scoped to the hierarchy discovered from the launch directory,
  not to every file of that name in the tree. Resolved: `CLAUDE_CONFIG_DIR` moves the whole config
  tree, so a hardcoded `~/.claude/CLAUDE.md` both flags a read that is now necessary and misses the
  redundant read of the configured path. Either location: a project that keeps its memory at
  `./.claude/CLAUDE.md` loads it at startup exactly as `./CLAUDE.md` would, so a set naming only the
  bare path lets the redundant read of the active file escape this check entirely. Phase A resolves
  the variable and inventories both project locations already; match it. The read spends a turn to
  retrieve text that is already present.
  **The `AGENTS.md` entry carries a fourth qualifier beyond those three, and it is not the
  displacement test.** Native reading also depends on whether `AGENTS.md` support is available in the
  session and on the instruction-files mode, so a session where support is unavailable, for any of
  the documented reasons, does not load
  the file even with no `CLAUDE.md` in sight, while one under the `claude-md-and-agents-md` setting
  loads it even **with** a `CLAUDE.md` beside it, which makes a read of it redundant where the
  displacement test alone would have exempted it. That setting is a user, `--settings` or managed
  one, so the value to resolve is the **effective** one across those scopes, never a single scope's
  copy.
  There, in the first case, an instruction to read it is the only thing that puts it in context,
  and flagging the read as redundant would propose deleting the load. Resolve the availability
  **and mode** conditions from the dated records in
  [agents-md-liveness.md](../../../reference/agents-md-liveness.md), before flagging an `AGENTS.md` read, and where **any of them**
  cannot be resolved for the session under audit, leave the read alone, per this check's own
  residency rule below that an unestablished residency is not a finding.
- **Remediate:** cut the retrieval step and state the requirement the read was meant to satisfy.
- **Must NOT flag: anything that loads on demand rather than at startup.** The guarantee this check
  rests on covers the hierarchy *the main conversation loads*, which is not the whole memory family.
  **Nested `CLAUDE.md` and nested `CLAUDE.local.md` files in subdirectories, and path-scoped rules
  (`paths` frontmatter), load lazily when work reaches their scope**, in both filename forms, since
  the lazy-loading behavior is a property of the location rather than of the name. An instruction to
  read either one before operating in that package can be doing real work. Flag only when the
  specific file named is one of the startup-loaded set above; when a surface's residency is not
  established, leave it.
- **Must NOT flag:** an instruction to read a surface that is *not* auto-loaded: contributing
  guides, ADRs, CI workflow files, per-ecosystem convention docs, and an `AGENTS.md` that a
  `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the working directory or above it
  displaces **under the default instruction-files mode and that mode is in effect**, **and one that
  no file displaces but that the session still does not read natively, because `AGENTS.md` support is
  unavailable there or the mode is one of the two that read no `AGENTS.md`**. A repository with no
  displacing file loads its `AGENTS.md` at startup like a `CLAUDE.md` (v2.1.277 and later, where
  support is available), so resolve both halves, the displacement and the availability-and-mode
  condition recorded in [agents-md-liveness.md](../../../reference/agents-md-liveness.md), before
  exempting it or flagging it. Unresolved is a leave-alone, per the residency rule above. Those are ordinary progressive disclosure, **but only while no active startup
  import reaches them.** A startup file
  that carries `@docs/CONTRIBUTING.md`, or the `@AGENTS.md` the docs themselves recommend for an
  `AGENTS.md` repo, has that file expanded into context at launch, so the document is resident and
  an instruction to go read it is exactly the redundant retrieval this check exists to find.
  **Resolve the startup set's `@path` imports first**, recursively, to memory's documented maximum
  depth of four hops, and add what they reach to the loaded set; this exemption applies only to what
  no such import reaches. **Any read where the file is the operation's subject rather than its
  instructions**: auditing it, editing it, patching it, reporting on it, or anything else needing
  current disk contents. The startup copy is a snapshot taken at launch; another process can have
  changed the file since, and a pre-edit read cut on the grounds that "it is already in context"
  produces a patch against stale text. A rule restated in a
  delegation prompt for a subagent that starts without the user, project and local `CLAUDE.md`:
  the built-in Explore and Plan agents, and a custom agent whose definition sets
  `omitClaudeMd: true`. In such an agent's own body, an instruction to read the root `CLAUDE.md`
  is likewise not redundant. Pointer: [What loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  and the `omitClaudeMd` row of [Supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields).
  The page's system-prompt section disagrees with both on whether `CLAUDE.md` still loads under
  that field. As of: 2026-10-01. Recheck trigger: the page reconciles the two, or the field is renamed.
- **Source:** subagents, "What loads at startup": we treat a non-fork subagent's initial context as
  holding every level of the CLAUDE.md hierarchy *the main conversation loads*, except an agent
  whose definition sets `omitClaudeMd: true` (see the Must NOT flag above), and that qualifier
  is what bounds this check: memory documents lazy loading for path-specific rules and
  subdirectory files ("How CLAUDE.md files load"), so those are outside the guarantee. memory,
  "Import additional files", is what puts an imported supporting document inside it: imports load
  at launch with the file that references them and recurse up to four hops. We treat such an
  import as what carries an `AGENTS.md` into a session that cannot read it directly, and as the
  portable form on Windows, where the symlink alternative needs elevation. Pointer:
  <https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable> and
  <https://code.claude.com/docs/en/memory#share-one-file-with-other-coding-tools>. As of:
  2026-09-19. Recheck trigger: that section stops naming the import, or a release note names
  `AGENTS.md` loading.

### I15: Cross-surface instruction conflict

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all, but the unit is
a **pair**, so this row is answered by Phase B2 rather than by a per-surface lane.

- **Detect:** two instruction surfaces that both constrain the same decidable act and prescribe
  incompatible actions for at least one input firing both, with no resident text arbitrating between
  them. The unit of judgment is the pair, never one document read alone, which is why the
  per-surface lanes are structurally blind to it. The five gates that make this checkable, the
  residency table gate 1 resolves against, and the precedence table separating what the docs settle
  from what they leave unresolved all live in
  [conflict-criteria.md](conflict-criteria.md); that file is this row's adjudication procedure.
- **Comparison set:** every pair drawn from the surfaces Phase A inventoried, including the ones it
  recorded as *skipped*, which are plugin-cache content, managed materializations, and org policy,
  since a contradiction is real whether or not this repository may edit either side. Resolve `@path` imports
  and symlinks to their targets before pairing, so an imported file is compared as part of the
  surface importing it rather than as a separate one.
- **Excluded from the comparison set:** files that are not Claude Code instruction surfaces here.
  An `AGENTS.md` is excluded only while a `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in
  the working directory or above it displaces it **under the default instruction-files mode** and no
  import reaches it: then it shapes no behavior here, so a divergence between it and a `CLAUDE.md`
  is not a conflict this check reports. Where nothing displaces it, Claude Code reads it as the
  project instructions and it is in the set like any other surface. **So does the
  `claude-md-and-agents-md` mode**, under which both files load and a displaced `AGENTS.md` shapes
  behavior anyway, which is the case where excluding it would drop a genuine contradiction between
  the two files. **The mode is the second question, not the only one.** This clause's own reason for
  excluding, that the file "shapes no behavior here", is exactly what an unavailable-support session
  produces, under any mode, and what the `claude-md` and `managed-only` values produce under any
  displacement answer: the file is not read, so a divergence between it and
  a `CLAUDE.md` is not a conflict either, and keeping it would report one against a surface nothing
  loads. Exclude on a condition known to rule the file out, and pair it only when every condition is
  satisfied. I15 is a finding lane, so **an unresolved residency is a leave-alone rather than a pair
  to judge**, which is what gate 1 already does with every other surface whose residency is not
  established. Both carry their dated records in
  [agents-md-liveness.md](../../../reference/agents-md-liveness.md).
- **Remediate by scope**, never by picking a winner the docs do not name. Where the precedence table
  cites a documented order, name the winner and its source. Where it does not, report the pair as
  `unresolved` with both anchors quoted and let the operator choose. Where the same conflict keeps
  recurring, offer the mechanism route, a `PreToolUse` hook, a `permissions.deny` rule, or a skill's
  own `disallowed-tools`, since a mechanism outranks instruction text.
- **Must NOT flag:** two surfaces that can never be resident together (that is orphaned instruction
  drift, reported separately). Different observables sharing a keyword. The same verb over different
  objects. An absolute carrying its own exception beside a directive presupposing that exception. A
  pair one of whose sides already states which wins. The full set with worked instances is in
  [conflict-criteria.md](conflict-criteria.md).
- **Source:** memory, "Write effective instructions" (contradicting rules and an arbitrary pick),
  which is why an unarbitrated pair is a finding rather than a stylistic note. We also treat a
  conflict as taxing reasoning even when no arbitrary pick occurs (correlate with the
  context-engineering blog under Sources, its "Unhobbling Claude" section).

### I16: Definition-site locality

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** an instruction that governs one named thing, such as a tool, a script, a subsystem,
  or a skill, living somewhere other than that thing's own definition: a rule about tool X in a
  global always-loaded file rather than beside X.
- **Different axis from I3, and both can fire on one instruction.** I3 is load *timing*; this is
  definition-site *locality*. An instruction can be correctly deferred, already in a skill or a
  path-scoped rule, and still sit away from the thing it governs.
- **Must not flag:** an instruction that genuinely applies across the whole target, which is I3's
  broad-applicability case and not a locality defect; or one whose subject has no definition site to
  sit beside.
- **Remediate:** move it beside its subject: the skill body, the agent definition, the tool's own
  documentation. **The destination must be a surface Claude loads.** This check diagnoses locality,
  not load timing, so a move that lands an always-loaded instruction in an ordinary README or
  reference file silently drops the behavior it enforced unless Claude independently reads that file.
  Where the subject's definition site is not itself loaded, propose the colocated text *plus* a
  retained one-line pointer on a loaded surface that triggers reading it, never a bare move.
  Reported only, never fix-applied, per the `OPINION` policy above.
- **Source:** none. No official page states definition-site locality, which is why this check is
  `OPINION`-tier. The *routing* half, which surface a class of content belongs in, is documented
  at features-overview, "Compare similar features", and is I3's concern, not this check's.

### I17: Thinking disabled where the model forbids it

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped.
Promotion gate MET: the claim is stated on a model-agnostic feature page, not in a model guide.
**The model ranges are Detect conditions, not a `Model scope` annotation.** The pairing arm is an
Opus 5 range; the outright-disable arm is a set spanning three families (Opus, Sonnet, and Fable
and Mythos), listed in the second arm below. The annotation's exact-string matching has no range
form. Annotating `opus-5` would
make the row inert on the next generation while the restriction still holds, and no single
annotation spans two disjoint families at once. I20 handles a model range the same way.

Each row below carries its own decisive source; they share a subject, not a citation.

**Base row: the configurations the model rejects.** Three arms with different shapes: a pairing
that fails only at the top of the effort ladder, a disable that fails at every level, and an API
thinking setting that refuses the top levels and per-turn effort changes. All three are `error`,
since each prescribes a request the model refuses.

- **Detect:** a surface that recommends, documents, or sets a **thinking-disable surface**, meaning
  `MAX_THINKING_TOKENS=0`, `alwaysThinkingEnabled: false`, the `/config` global toggle, the
  `Alt+T` / `Option+T` session toggle, or API `thinking: {"type": "disabled"}`, together with
  `xhigh` or `max` effort, on Claude Opus 5 or a later model. Both operands are configuration
  literals. Fire on the API form and on the harness forms alike: in neither does the prescribed
  level reach the model, so the finding and its remediation are the same for both. What Claude
  Code sends in place of the prescribed level is behind the pointer.
  Pointer: for the harness outcome, see
  [model configuration: extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking)
  and [errors: effort isn't available with thinking turned
  off](https://code.claude.com/docs/en/errors#effort-isnt-available-with-thinking-turned-off).
  As of: 2026-10-01. Recheck trigger: either section changes what Claude Code sends when thinking
  is off and the prescribed level is `xhigh` or `max`.
- **Effort literals do not all reach every surface, and the literal set is not the whole set.**
  Count `max` wherever text sets it through `CLAUDE_CODE_EFFORT_LEVEL`, `--effort`, `/effort`, or
  skill and subagent `effort` frontmatter, the frontmatter case being a surface this skill already
  inventories. **Count two `ultracode` forms as `xhigh`:** `--effort ultracode`, and
  `effortLevel: "ultracode"` sent through the Agent SDK. Count `/effort ultracode` and the
  `ultracode` setting only where the level already in effect is `xhigh` or `max`. Match on the
  effort that reaches the request, not on the spelling. **Narrowed on 2026-10-01:** this row
  formerly counted all four `ultracode` forms as `xhigh`. It now counts `/effort ultracode` and the
  setting only on the condition above, because the row matches the effort that reaches the request
  and we treat those two forms as leaving the level in effect unchanged.
  Pointer: for which ultracode forms set the level, see
  [model configuration: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level).
  As of: 2026-10-01. Recheck trigger: that section changes which ultracode forms set the effort
  level.
- **Second arm: the models that reject the disable outright, at every effort level.** We treat
  `thinking: {type: "disabled"}` as failing whatever effort is in force on this row's set: Claude
  Opus 5.5, Claude Sonnet 5.5, Claude Fable 5.1, Claude Mythos 5.1, Claude Fable 5, Claude Mythos
  5 and Claude Mythos Preview. On that set the disable surface alone is the finding and no effort
  operand has to be present for the request to fail. Read the effort operand as a condition that
  *narrows* the Opus 5 arm, never as a precondition the whole row inherits. Carried across, it
  would pass a surface prescribing thinking-off at `high` on Fable 5.1 as compliant. On Sonnet 5.5
  the remediation also points at the guide's thinking-off alternative, which the third arm bounds.
  **Only the API form belongs to this arm.** On **the models in I17-a's no-effect
  set** the harness thinking-disable surfaces fail differently, and that failure is I17-a's, not
  this row's: we treat thinking as unable to be turned off there, and the session toggle,
  `alwaysThinkingEnabled` and `MAX_THINKING_TOKENS=0` as silent no-ops rather than errors. **For
  the Mythos models the harness pages state nothing**, so this row makes no claim about their
  harness surfaces in either direction; the API reject is the whole of what is stated for them.
  Pointer: for the per-model accepted values, see [thinking: configuring
  thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#configuring-thinking)
  and the [troubleshooting
  table](https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting#supported-models);
  for the harness no-ops, see
  [model configuration: extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking).
  As of: 2026-10-01. Recheck trigger: a model gains or loses a 400 for `"disabled"` in either
  table, or the harness no-op list changes.
- **Third arm, API requests only: `between_tools` at a level or with a change it refuses.** Flag
  instruction text that prescribes, or a code sample it tells the reader to send, a request to
  Claude Sonnet 5.5 carrying `thinking: {"type": "between_tools"}` together with `xhigh` or `max`
  effort, or together with a per-message effort change. No Claude Code surface sets
  `between_tools` (see I8-c's declined `sonnet-5-5` widening), so this arm reaches only instruction
  surfaces that prescribe Messages API requests, such as a skill or reference doc that tells the
  reader what to send. A prompt in application source that sends `between_tools` is not this
  catalog's: it belongs to the bundled `claude-api` skill (SKILL.md, "Boundary"), the same split
  I8-c records. Pointer: for the levels and changes
  `between_tools` refuses, see the [Sonnet 5.5
  guide, running without up-front
  thinking](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#running-without-up-front-thinking)
  and [thinking: configuring
  thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#configuring-thinking).
  As of: 2026-10-01. Recheck trigger: either page changes which effort levels `between_tools`
  accepts, or per-message effort changes become valid with it.
- **Remediate:** on the Opus 5 arm, lower the effort to `high` or below, or leave thinking on, and
  state which, since the pairing has no third resolution. **On the second arm there is only one
  resolution: leave thinking on.** No effort level permits the disable on that set, so a
  remediation that offers the reader the choice sends them to a request that still fails. The one
  addition is Sonnet 5.5 in a prescribed API request: point the reader at the third arm's guide
  pointer for the model's thinking-off alternative rather than naming a setting here. **On the
  third arm**, drop whichever operand the surface does not need, the top effort level or the
  per-turn change; where the surface needs both, replace the request shape with the guide's form at
  the third arm's pointer.
- **Scope, and where the config check lives:** this row audits **instruction text**. Any arm
  expressed as *settings keys* is a config-mechanics finding and belongs to
  `harness-config:audit`, per this skill's own routing. An instruction-content catalog that also
  scanned settings files would claim authority a sibling already holds. Instruction text that
  happens to *live* in a settings file, such as a prompt-type hook's injected text, stays here: the
  discriminator is whether the content instructs, not which file holds it.
- **Must NOT flag:** `effortLevel: max` as a literal to hunt **in instruction text**. We rely on
  the settings schema rejecting `max` for that key (pointer: the SchemaStore document
  `https://json.schemastore.org/claude-code-settings.json`, its `properties.effortLevel` entry; as
  of: 2026-10-01; recheck trigger: the schema accepts `max` there), so a schema-aware editor flags
  the value where it is actually written, and an instruction-text auditor sent after the literal
  finds nothing and learns nothing. The value is writable, not unreachable: the schema is
  advisory and the harness reads a file that violates it, which is why the settings-file check is
  `harness-config:audit` category H rather than absent. **A document that states any arm to
  describe or forbid it**, such as this row, a model-adaptation delta chapter, or a verification
  record quoting it, on the same audience test I8-b applies: any arm prescribed inside an
  operative directive is a finding; a document *about* it is not. **The bare `ultracode` prompt
  keyword.** Instruction text telling a reader to include it in a typed prompt runs one task as a
  workflow without changing the session's effort level, so no effort reaches the request and the
  rejected pairing never assembles. **A thinking-disable surface named with no effort level in reach
  of it, on the Opus 5 arm only**, where the pairing is what fails. On the second arm that is the
  finding itself, so this fence is scoped to the arm that earns it rather than to the row.
- **Source:** effort, its Opus 5 section (the `xhigh`/`max` disable rejection). Corroborated at
  thinking-troubleshooting, which supplies the model range and the per-request enforcement. The
  per-surface value sets are read from the surfaces' own pages: settings for `effortLevel`,
  environment variables for `CLAUDE_CODE_EFFORT_LEVEL`, skills and subagents for `effort`
  frontmatter, and model configuration for `/effort`, the session and global thinking toggles, and
  ultracode, the last enumerating the three routes that turn the *setting* on (`/effort`,
  `--effort`, `--settings` / Agent SDK). The keyword's separation from the setting is read from
  workflows, "Ask for a workflow in your prompt". The second arm is thinking's per-model table,
  where those models refuse `"disabled"` with no effort qualifier while Opus 5 refuses it only at
  the top levels: that is what makes the arm unconditional rather than a wider pairing, and why
  the two are read as separate arms rather than one range.
- **Local coverage of the second arm, measured 2026-08-04: zero operative instances in the
  repository that authored it.** The disable literal occurs six times across four files: three in
  this catalog, once in the Opus 5 model-adaptation delta chapter, twice in changelog entries.
  Every one is a document *about* the restriction, which is the audience-test fence above rather
  than a passed check. **Re-measure when** a surface here begins prescribing a thinking-disable
  instead of describing one.
- **As of 2026-08-04** for the Opus 5 pairing as first written (those pages read as raw markdown);
  the harness consequence, the `ultracode` forms, the second arm's model set and the third arm
  carry their own 2026-10-01 records above. **Recheck trigger:** the effort level set gaining or
  losing a name, the set of `ultracode` forms that reach `xhigh` changing, the restriction's model
  range moving, or the set of models that reject the disable outright changing.

**Row I17-a: `MAX_THINKING_TOKENS=0` presented as a universal off switch** · Tier `mechanical` ·
Severity `warning`.

- **Detect:** text stating or implying that `MAX_THINKING_TOKENS=0` turns thinking off generally,
  naming neither exception this row keeps: the no-effect set (the models on which thinking cannot
  be turned off, read live from the extended-thinking pointer below), or third-party providers.
  Also flag text treating `CLAUDE_CODE_DISABLE_THINKING` as equivalent to it, and text presenting
  the session thinking toggle or `alwaysThinkingEnabled` as turning thinking off on a model in the
  no-effect set. For what each control does on each model and provider, follow the pointer.
- **Remediate:** carry the exceptions with the claim, or point at the page instead of restating it.
- **Adjacent axis:** this is also a harness-capability claim, so **I12 can fire on the same line**.
  I12 asks whether the claim matches its page; this row asks whether a reader following it gets the
  behavior they were promised. Report both when both hold.
- **Must NOT flag:** a mention that already names the whole no-effect set as the page lists it on
  the audit date, links that section for it, or names the third-party exception; any one is
  enough. A mention naming only part of the set names neither and still fires. A bare reference to
  the variable making no claim about its reach.
- **Source:** environment variables, the `MAX_THINKING_TOKENS` and `CLAUDE_CODE_DISABLE_THINKING`
  rows, and model configuration, "Extended thinking" (the no-effect set, the toggles, and the
  third-party behavior). Pointer: [environment variables:
  variables](https://code.claude.com/docs/en/env-vars#variables), those two rows (read whole per
  the fetch route under Sources), and [model configuration: extended
  thinking](https://code.claude.com/docs/en/model-config#extended-thinking).
- **As of 2026-10-02** for the extended-thinking section (read as raw markdown that day; this row
  names no model and takes the no-effect set from it at audit time), **2026-10-01** for the
  environment-variable rows. **Recheck trigger:** the extended-thinking anchor moving or that
  section no longer listing which models cannot have thinking turned off, or the third-party
  behavior changing.

**Row I17-b: mid-session thinking or effort change prescribed without its cost** · Tier
`mechanical` · Severity `info`.

- **Detect:** an instruction directing a reader to change **effort**, or the **thinking
  configuration**, part-way through a session, with no statement of the prompt-cache cost beside
  it. The thinking half covers switching among `adaptive`, `enabled` and `disabled`, and changing
  `budget_tokens`. For why such a change costs the cache, follow the Source.
- **Must NOT flag: a Claude Code surface prescribing an *effort* change.** We leave that cost to
  Claude Code's own handling of an effort change, so the surface owes no warning of its own. Nor
  flag a change prescribed *with* its cost stated, which is the remediation.
  Pointer: for how Claude Code handles an effort change, see
  [prompt caching: changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level).
  As of: 2026-10-01. Recheck trigger: that section stops covering how Claude Code handles the
  cache cost of an effort change, or Claude Code's changelog names a change to that handling.
- **On an API surface, the remediation may offer the per-message effort route, never with
  `between_tools`.** Offer it where the model supports it. Never offer it to a surface that sends
  `between_tools`: that combination is I17's third arm, not this row. Pointer: for the
  per-message route, see [effort: change effort mid-conversation
  (beta)](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta);
  for the `between_tools` combination, see the [Sonnet 5.5 guide, calibrate
  effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#calibrate-effort).
  As of: 2026-10-01. Recheck trigger: per-message effort leaves beta or changes its cache
  behavior, or `between_tools` starts accepting it.
- **Reach differs by half, and this is the whole of it.** The effort half reaches every surface, with
  Claude Code surfaces carved out above. **The thinking half reaches API and Agent SDK surfaces
  only.** A Claude Code surface prescribing a mid-session thinking toggle is **out of reach of
  this row**, neither excused by the effort carve-out nor flagged by the thinking half.
- **Why the carve-out does not simply extend to thinking, and why the row stops short instead.**
  The carve-out's pointer covers effort changes only, and on our reading of 2026-10-01 no Claude
  Code page covers what a mid-session thinking change costs. So we neither assume Claude Code
  handles a thinking toggle the way it handles effort nor flag a cost no source states: out of
  reach rather than covered. **Re-scope when** a Claude Code page covers what a mid-session
  thinking change costs.
- **Why the thinking half is not I17-c, and why both can fire, on accepted changes only.** This
  row asks what a change *costs*. A switch among the modes, or a change to `budget_tokens`,
  restarts the cache when the new configuration is accepted and a turn runs under it. I17-c asks
  whether a fixed budget is a valid control on the target model at all, and where it applies the
  cost claim may never materialize: an API request the model rejects with a validation error
  completes no turn, and a harness value the model silently ignores changes no configuration. In
  both cases the reader's actual outcome is I17-c's finding alone, and adding this row's cache-cost
  remediation would be a second, misleading instruction. So: a mid-session change between
  configurations the model accepts gets this row; a prescription I17-c already condemns as not a
  valid control gets I17-c alone. Report both only where a surface prescribes both an invalid
  control and, separately, an accepted mid-session change.
- **Local coverage of the thinking half, measured 2026-08-04: zero operative instances here.** The
  session-toggle and `budget_tokens` literals appear only in this catalog, in two model-adaptation
  delta chapters, and in changelog entries, which are descriptions, not prescriptions.
- **Remediate:** name the re-read cost, and prefer choosing both dials at session start. On an API
  surface, offer the per-message effort change where the model supports it and the request does
  not send `between_tools`.
- **Source:** prompt caching, "Changing effort level" (the effort half in Claude Code). The thinking
  half, and the API effort half, point at [thinking: thinking and prompt
  caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching).
- **As of 2026-08-04** for the thinking half (that page read as raw markdown); the carve-out and the
  API per-message route carry their own 2026-10-01 records above. **Recheck trigger:** effort or
  the thinking configuration leaving the cache key on the thinking page, or a Claude Code page
  starting to cover what a mid-session thinking change costs.

**Row I17-c: fixed thinking budget prescribed where adaptive reasoning ignores or rejects it** ·
Tier `mechanical` · Severity `warning`. Unscoped. Promotion gate MET: the claim is stated on
model-agnostic surface pages (thinking, environment variables, model configuration), not in a model guide. **The model
ranges below are Detect conditions, not a `Model scope` annotation**, for the reason I17 base states.

- **Detect:** instruction text directing a reader to control thinking *depth* with a fixed token
  budget on a model that always uses adaptive reasoning: this row's set is Opus 4.7 and later
  (Opus 4.7, Opus 4.8, Opus 5, Opus 5.5), Sonnet 5 and later (Sonnet 5, Sonnet 5.5), and the Fable
  and Mythos 5-series models (Fable 5.1, Fable 5, Mythos 5.1, Mythos 5). Two arms, with opposite
  failure modes:
  - **Harness arm: silent no-op.** A nonzero `MAX_THINKING_TOKENS`, or
    `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` offered as the way to make one take effect, on a
    model in the set. We rank this the worse of the two arms because nothing tells the reader it
    failed.
  - **API arm: hard 400.** `thinking: {type: "enabled", budget_tokens: N}`, or prose presenting a
    thinking budget as a tunable number, on any model in the set. Claude Mythos Preview is outside
    this row's set.
  Pointer: for the API arm, see [thinking: configuring
  thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#configuring-thinking)
  (its `"enabled"` column); for the harness arm, see the `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`
  row of [environment variables:
  variables](https://code.claude.com/docs/en/env-vars#variables) and [model configuration:
  adaptive reasoning and fixed thinking
  budgets](https://code.claude.com/docs/en/model-config#adaptive-reasoning-and-fixed-thinking-budgets).
  As of: 2026-10-01. Recheck trigger: a model gains or loses a 400 for `"enabled"` in that column,
  or the set of always-adaptive models changes.
- **Why this is not I17-a.** That row is about `MAX_THINKING_TOKENS=0`, the claim that thinking can
  be turned *off*, and whether the exceptions travel with it. This row is the claim that thinking
  depth can be *set to a number*. Different literal, different promise, different failure; both can
  fire on one surface that gets the whole variable wrong, and both should be reported when they do.
- **Must NOT flag: a claim carrying its own gate, of either kind.** Text naming Opus 4.6 or Sonnet
  4.6, where the fixed-budget mode is live and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` does exactly
  what it says, is correct rather than stale. **So is text scoped to a Claude Code release before
  v2.1.111**, which is where the variable lost its reach over the adaptive-reasoning models. The
  gate here is a version as well as a model set, and I12's precondition rule already says a claim
  scoped to a pinned older release is measured against that release. This fence matters more here
  than usual: the tempting shape of this check is a bare grep for the variable name, which would flag
  every accurate piece of documentation about it. **The finding is the missing gate, never the
  mention.**
- **Must NOT flag:** a bare reference to either variable making no claim about its reach. A document
  *about* the pattern, such as this row, a model-adaptation delta chapter, or a verification record,
  on the audience test I8-b applies. **The budget expressed as a settings key, an environment
  assignment, or an SDK request field** rather than prescribed in instruction text: that is a
  config-mechanics or source-code finding on the same discriminator I17 base, I21 and I22 apply, and
  this catalog audits instruction text.
- **Remediate:** point at the effort parameter as the depth control on adaptive-reasoning models, or
  carry the model gate with the claim. We do not offer effort as a like-for-like budget
  replacement: effort is a separate control, not a thinking budget (effort page).
- **Source:** environment variables, the `MAX_THINKING_TOKENS` and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` rows (nonzero values ignored on adaptive-reasoning
  models; the latter's loss of reach from v2.1.111 over the always-adaptive models). The version
  qualifier is the second half of the gate fence above. Model configuration, "Adaptive reasoning
  and fixed thinking budgets", covers the same partition from the other side, including the Opus
  4.6 and Sonnet 4.6 revert that is the fence above. The API arm's model range is read from
  thinking's per-model table (the Pointer under Detect); the migration-guide URL that first carried
  it is now an index of per-model guides. Corroborated for this model generation by the Sonnet 5
  guide, "Calibrating effort and thinking depth".
- **As of 2026-10-01** for the model set under Detect; **as of 2026-08-04** for the v2.1.111
  version fence, which the environment-variables row no longer states (re-read 2026-10-01), so that
  fence rests on its first reading. **Recheck trigger:** the set of models that always use adaptive
  reasoning changing, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` regaining or losing reach, or manual
  extended thinking being reinstated on any model in the range.

**Row I17-d: tool reliance with thinking disabled and no explicit tool nudge** · Tier `behavioral` ·
Severity `warning` · Model scope: `sonnet-5`.

- **Detect:** a surface that both (a) prescribes running with thinking off, meaning any
  thinking-disable surface I17 base enumerates, or a workload the surface states runs
  thinking-disabled, and (b) depends on the model reaching for tools (search, retrieval, self-verification loops, agentic tool
  chains) while stating no explicit instruction about when and how to use those tools. We treat
  thinking-off as reducing the model's reach for tools, so a brief that turns thinking off and then
  relies on default tool reach depends on a disposition that configuration reduced, and the
  failure is silent: fewer tool calls, not an error.
- **Remediate:** add an explicit tool nudge to the system prompt, describing which tools, when, and
  why, or leave thinking on. Effort is a second lever: we treat `high` or `xhigh` as raising tool
  use in agentic search and coding.
- **Must NOT flag:** a thinking-disable with no tool dependence. A tool-dependent surface that
  already instructs its tool use explicitly. That is the remediation, present. A surface with no
  control over and no claim about the thinking configuration, whose tool reliance runs under the
  default (thinking on). A document *about* the pattern, such as this row, a model-adaptation delta
  chapter, or a verification record, on the audience test I8-b applies.
- **Why scoped:** the coupling claim is stated only in the Sonnet 5 guide. The Opus 4.8 guide's
  "Tool use triggering" section covers a different default for its model with no thinking-off
  coupling, so it is not a second statement of this claim; the halves the two guides do share
  (effort as a tool-usage lever, describe-why-and-how tool instruction) are general advice, not
  this row's detect condition.
- **Source:** Sonnet 5 guide, "Tool use triggering" (the coupling, the nudge, and the effort
  lever).
- **As of 2026-08-08** (our probe of the Sonnet 5 guide, 15,864 bytes, MD5
  `6d23959f0ed226feb06bf20c314029e3`, and, for the scope negative, the Opus 4.8 guide, 15,905
  bytes, MD5 `6b9db5b784ad6a7b2e6307c1481b8be9`, both read as raw markdown). **Recheck
  trigger:** a second model guide stating the thinking-off tool-reach coupling, which would meet the
  promotion gate and unscope this row.
- **Re-justified 2026-10-01 against the current models:** `sonnet-5` stays (see "Tokens of models
  that are no longer current"). The row does not widen to `sonnet-5-5`: that model is in I17-a's
  no-effect set, so half (a) of Detect cannot hold there, and our probe of its guide that day (read
  whole as raw markdown; no artifact stored) found no thinking-off coupling. Tool-discouraging text
  on that target is I36's. Pointer: [model configuration: extended
  thinking](https://code.claude.com/docs/en/model-config#extended-thinking) for the no-effect set;
  [Prompting Claude Sonnet
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5),
  the whole page, for the negative. As of: 2026-10-01. Recheck trigger: Sonnet 5.5 leaves the
  no-effect set, or its guide states a thinking-off tool-reach coupling.

### I18: Thinking blocks altered on the way back to the model

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped.
Promotion gate MET: the round-trip protocol is stated on a model-agnostic feature page, not in a
model guide.

Two rows, in opposite directions: the base row is what a surface does to blocks it *has*, and I18-a
is what a surface believes about blocks that are *not there*. They share a subject, not a citation.

**Base row: blocks altered on the way back.**

- **Detect:** instruction text directing an agent, a script, or a reader to handle assistant content
  blocks in a way that breaks the round-trip protocol. Three shapes:
  1. **Dropping the `signature`.** An instruction to reconstruct, summarize, re-serialize, or
     hand-assemble an assistant turn before sending it back, where the reconstruction does not
     carry each `thinking` block's `signature` through unchanged. The server decrypts that field to
     rebuild the reasoning; a block without it is not the block the model produced.
  2. **The type-filter smell.** An instruction to select content blocks by testing
     `block.type == "thinking"` when round-tripping tool-use responses. The predicate silently
     omits `redacted_thinking` blocks, which the protocol requires back unchanged.
  3. **Within-turn echo integrity.** An instruction to reorder, edit, truncate, or partially drop
     the consecutive `thinking` blocks of the latest assistant message, including "keep only the
     last one" and "strip thinking before resending" advice. We treat any altered block as a 400
     rejection.
- **Reach: this is wider than Messages API client code.** Any instruction whose output eventually
  becomes a request body is in scope: Agent SDK callers, harness integrations, and **tooling that
  parses, excerpts or rewrites a stored transcript that will later be replayed or resumed**. What
  puts a surface in scope is a path back to the model, not the file format it reads.
- **Remediate:** echo the assistant `content` array back unchanged rather than rebuilding it; where
  blocks must be selected, select by what is being *excluded* rather than by an equality test on one
  type name; where a transcript is being read for analysis only, say so, since a read that never
  re-sends is outside the protocol entirely.
- **Must NOT flag:** an instruction to read or analyze a transcript with no path back to the model:
  metrics extraction, retrospectives, search. **A `redacted_thinking` clause premised on those blocks
  being present in local transcripts**, which is a separate and unevidenced claim; this row's
  concern is only that a type filter would drop them if the API returned them. Pruning of *prior*
  turns' thinking, which the API does for you and which the page explicitly allows outside tool use.
  **A document that names the type-filter predicate to describe the smell**, such as this row,
  a model-adaptation delta chapter, or a verification record quoting it, on the same audience test
  I8-b applies: the predicate quoted inside an operative directive is still operative and is a
  finding; a document *about* the pattern is not.
- **Source:** Thinking, "Preserving thinking blocks" (echoing blocks back complete and unmodified,
  and within-turn sequence integrity); same page, "Thinking encryption" (the `signature` field)
  and "Redacted thinking blocks" (what a type-equality filter drops).
- **Local coverage, measured 2026-08-02: zero instances of all three shapes in the repository that
  authored this row**, which ships it consumer-facing and unexercised by its own corpus. Stated so
  the absence reads as an as-of measurement rather than as a passed check. **Re-measure when** a
  round-trip or transcript-replay path lands here.
- **As of 2026-08-02** (the Thinking page read as raw markdown). **Recheck trigger:** a
  content-block type joining or leaving the set the protocol requires echoed back.

**Row I18-a: a leading thinking block treated as required where the model does not require one** ·
Tier `mechanical` · Severity `warning`.

- **Detect:** instruction text asserting, or directing work premised on, a validation rule that
  assistant turns must begin with a thinking block. Three shapes:
  1. **Reinsertion.** An instruction to insert, synthesize, or restore a leading `thinking` block
     when assembling history from mixed sources, so that each assistant turn starts with one.
  2. **History rewriting on resume.** An instruction to rewrite, normalize, or discard a
     conversation because it began without thinking or ran under a different thinking
     configuration.
  3. **Presence-assuming logic.** An instruction to read, index, or branch on an assistant turn's
     first content block as though it were a `thinking` block. We treat an assistant turn produced
     without thinking as having no such block, and one conversation as able to mix both kinds.
- **Why the belief is a finding and not a harmless one.** The remediation a reader reaches for is
  fabrication, and a hand-built block carries no valid `signature`, which is the base row's shape 1,
  and a rejected request. This row is therefore the upstream cause of the base row's violation, not
  a restatement of it; report both when a surface states the premise *and* acts on it.
- **Remediate:** send history back as it is, without reshaping it, and treat a thinking block as
  optional per assistant turn, in tests too, where a no-thinking turn is the case the assumption
  hides.
- **Reach: the base row's, unchanged, and for all three shapes.** A path back to the model is what
  puts a surface in scope, not the file format it reads. **Presence-assuming logic that only ever
  reads is out of reach rather than excused.** The page's caution sits in the request/response
  frame and says nothing about stored transcripts, and whether a harness transcript carries
  thinking blocks at all is unestablished; the harm there would in any case be the consumer's own
  logic rather than a rejected request, which is a code-correctness matter this catalog does not
  audit. **Re-scope when** the stored transcript's content-block shape is documented.
- **Must NOT flag: text scoped to a legacy manual thinking budget AND to the final assistant
  turn**, where the requirement is real. The page carves it out itself, and we treat the
  enforcement as exactly that wide: only the last assistant turn, and only when the request has
  thinking on. A
  legacy-scoped instruction demanding a leading block on *every* assistant turn over-requires past
  its own source and still flags. The gate is the model's thinking mode plus the turn it names, not
  the sentence's confidence, and as in I17-c **the finding is the missing gate, never the
  mention.**
  **The base row's own advice**, which is not this row's inverse: we read the relaxation as about
  validation, not about what to send, so an instruction to return the blocks you *have* untouched,
  tool-use turns above all, is correct and stays correct. Reading this row as
  license to drop blocks inverts both rows at once. A document *about* the assumption, on the
  audience test I8-b applies.
- **Source:** Steering thinking, "Turn validation" (the relaxation, with one consequence per shape
  above, and the legacy carve-out the fence above relies on); the presence half is the same page,
  "How Claude decides when to think".
- **Why this page is cited and not the sibling.** The Thinking page carries the same pair, but
  compressed into one passage inside "Thinking with tool use" (manual-mode enforcement and the
  adaptive-mode relaxation). That corroborates this row; it does not carry it. Steering thinking
  is where the relaxation is stated operatively, with the three history-shape consequences the
  detect shapes are drawn from, plus the presence caution, so it is cited as decisive and the
  sibling as corroboration. Separate from both is that page's *strip* claim about turn structure:
  we read it as server-side degradation of a request, not a rule about what history a caller may
  send, and it licenses nothing here.
- **Local coverage, measured 2026-08-04: zero operative instances here**, on the same footing as the
  base row, since nothing in this repository assembles, rewrites, or replays history back to the
  model.
  The one transcript consumer, `session-flow`'s retro parser, selects blocks by testing each item's
  own `type` rather than by position, so it is correct by construction rather than by this rule.
  Stated as an as-of measurement, not a passed check. **Re-measure when** a history-assembly or
  replay path lands here.
- **As of 2026-08-04** (the Steering thinking page read as raw markdown). **Recheck
  trigger:** the turn-validation relaxation narrowing, or the set of models that enforce a leading
  thinking block changing.

### I19: Restated external benchmark figure with no recheck trigger

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** a surface restating a named benchmark's score, ranking, or suite version, carrying no
  recheck trigger: a model comparison table, a launch-figure list, a "state of the art on X" claim.
  Benchmark figures are attested by an announcement at a moment: suites revise, vendors
  report against a different harness, and a later release reorders the table, so a figure with no
  stated re-derivation event silently becomes a claim about the past told in the present tense.
- **Remediate:** either point at the vendor's announcement and restate nothing, or keep the figure
  as the surface's own recorded decision and attach the record beside it: a pointer to the exact
  source section the figure came from, the as-of date, and a recheck trigger naming an observable
  event (a new frontier-model release, a suite version bump, a decision that would turn on the
  figure). Label the figures as launch-day snapshots where that is what they are; leaving them as
  history is a valid outcome and usually the right one.
- **Must NOT flag: a verbatim upstream baseline held for drift detection.** A vendored copy exists
  to be compared byte-for-byte against its source, so stamping it would corrupt the comparison it
  exists to serve. This is a genuine suppression, not a routing case, which is what distinguishes
  it from plugin-cache content and managed materializations: those are still flagged, and the
  finding becomes a routing recommendation to the owning repository. Flag the locally-owned surface
  that *restates* the figure, never the baseline it was restated from.
- **Must NOT flag:** a benchmark named as a pointer with no figure attached. A figure already
  carrying a trigger, whatever heading that trigger sits under.
- **Source:** none. No official page states that a restated benchmark figure needs a re-derivation
  event, which is why this check is `OPINION`-tier and off by default. The record shape it asks for
  (the decision, a pointer, an as-of date, a recheck trigger) is this monorepo's
  `docs/conventions/upstream-drift/README.md`; in a standalone install those parts, not the path,
  are the requirement.

### I20: Prefilled assistant response

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. The severity is
`error` because following the instruction produces a rejected request, the same consequence class
as I17 and I18, not because instances are expected to be common. **The unsupported model range is a Detect
condition, not a `Model scope` annotation**, for the reason I17 states.

- **Detect:** instruction text that tells a caller to prefill Claude's response, supplying a
  partial assistant message on the last turn so the model continues from it, where the run's
  resolved target model is a Claude 4.6 or later model, or Claude Mythos Preview. The classic uses
  are the tells: forcing a JSON or YAML shape, opening with `Here is the requested summary:` to skip
  preamble, steering around a refusal, resuming an interrupted generation, and re-injecting context
  as a pseudo-assistant reminder.
- **Remediate:** the technique is not deprecated advice but a rejected request. On current models a
  prefilled last assistant turn returns a 400. Replace it per use: state the output contract in the
  `user` turn or a structured-output facility for format control, ask directly for no preamble,
  prompt clearly rather than prefill past a refusal, and move context reinjection into the user turn
  or a tool.
- **Must NOT flag:** an assistant message anywhere other than the last turn, which is unaffected.
  **A document that names the technique or its tells to describe it as retired**, such as this
  row, a migration guide, or a model-delta chapter, on the same audience test I8-b applies: a prefill
  prescribed inside an operative directive is a finding; a document *about* prefill is not.
  Instructions targeting an explicitly pinned earlier model, which still supports it.
- **Source:** prompting best practices, "Migrating away from prefilled responses" (the unsupported
  model range, the 400, and what stays unaffected).
- **As of 2026-08-02** (that page read as raw markdown; the standalone prefill technique page
  redirected to the prompt-engineering overview). **Recheck trigger:** any change to
  that page, or the unsupported-model range moving.

### I21: Effort level pinned across a model change with no re-sweep

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all. Unscoped.
Promotion gate MET: the calibration property is stated **unqualified** on a model-agnostic feature
page, not in a model guide. That sentence alone clears the gate; the effort page's Opus 5 subsection
is cited below only for the remediation's wording, and its placement inside a per-model section does
not narrow a property its own page states generally. **The model range below is a Detect condition,
not a `Model scope` annotation**, for the reason I17 states.

- **Detect:** a surface prescribing a **durable** effort level that states no re-derivation when the
  pinned model changes: a fleet-wide or project-wide pin, a "set effort to X and leave it"
  instruction, a level tied to a named model lane. We treat the effort scale as calibrated per
  model, so a level name measured against one model is not the same setting on the next; a level
  carried across a model change is a pin nobody re-measured.
- **The consequence varies by model, which is why the range sits in Detect.** We treat Opus 5.5 as
  starting at `medium` unless an explicit choice sets a level, with a top-level `effortLevel` in
  the user settings file not counting for it (Opus 5, Fable 5.1 and older models still honor that
  key), and models released after Opus 5.5 as starting at their own default until `/effort` or the
  `/model` picker saves a level. Every model takes the level a top-level `effortLevel` sets in the
  project, local or managed file or through `--settings`, and `--effort` sets it for one launch.
  The model-config page no longer carries a first-run effort hold for Fable 5, Opus 4.8 or Opus
  4.7. The row fires on the missing re-derivation regardless of model; the hold is
  severity context, never a fence.
  Pointer: [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level).
  As of: 2026-09-28. Recheck trigger: that section changes which sources set a model's level, or
  the user-settings exemption for Opus 5.5.
- **Remediate:** attach the re-derivation to the pin, naming the model the level was measured
  against and stating that a model change re-opens it, or run a fresh effort sweep on the
  surface's evals rather than reusing carried-over levels.
- **Must NOT flag: a prescription of `high` where `high` is the resolved target's default.** We
  treat setting the default as equivalent to omitting the `effort` parameter, so on a model that
  defaults to `high` such a pin carries no measured calibration that could go stale.
  **The exemption keys to the resolved target, never to the wording.** In Claude Code every
  effort-capable model defaults to `high` **except Opus 5.5 and Sonnet 5.5, which default to
  `medium`, and Opus 4.7, which defaults to `xhigh`**, so when the run's resolved target is one of
  those the exemption lifts and a `high` pin is a finding, **including a broad model-agnostic
  "always use `high`" that names no model at all**. That broad pin is the sharper case rather than
  the excluded one: written where `high` was the no-op default and then carried to a model whose
  default differs, it silently becomes a step nobody measured, which is this row's subject exactly. A resolved target
  always exists, because the skill body aborts rather than run against an unresolved one, so this
  fence never has to guess which side of it a surface falls on. **The exemption speaks to
  calibration staleness only, never to level adequacy:** a model guide may recommend running above
  the default for named lanes, as the Opus 4.8 guide does when it recommends `xhigh` for coding and
  agentic use, and whether a `high` pin under-serves such a lane is that surface's sizing decision,
  outside this row's subject.
- **Must NOT flag: a per-task or single-turn effort choice**, such as "reach for `xhigh` on hard
  problems", `ultrathink`, or `ultracode`, which selects a level for one piece of work rather than
  pinning one. This row is about durable pins.
- **Must NOT flag: `effort:` frontmatter and `effortLevel` settings keys as such.** Those are
  configuration values, and I17's discriminator applies unchanged: this row audits **instruction
  text**; the pin expressed as a config key is a config-mechanics finding belonging to
  `harness-config:audit`. Instruction text that merely *lives* in a config file stays here.
- **Must NOT flag: schema documentation and its illustrative samples.** A field table enumerating a
  config key's accepted levels, and the worked example beside it, exist to show the **shape** a
  consumer must fill in. The level in the sample is a placeholder demonstrating syntax, not a level
  this surface measured and prescribes. This is a separate fence from the one above and does not
  depend on it: the sample is quoted inside documentation prose rather than living in a config file,
  so the previous fence would not reach it. The fence ends where the demonstration does. A surface
  that documents the field **and then tells the reader which level to put there** is prescribing, and
  the prescription is in scope.
- **Must NOT flag: a document *about* the calibration property**, such as this row, a model-delta
  chapter, or a verification record, on the audience test I8-b applies. Nor a level **reported as a
  named third party's practice** rather than prescribed to the reader: a practitioner's stated setup
  is `OPINION`-tier testimony, not a pin the surface owns.
- **Source:** model configuration, "Choose an effort level" (the per-model calibration, stated with
  no model qualifier, and the whole basis for the check) and "Adjust effort level" (the resolution
  order and the per-model defaults this row keeps as its own settings above). Effort, "How effort
  works" and its per-model sections, supplies the remediation and the equivalence of the default
  to omitting the parameter.
- **As of 2026-09-28** (our probe: both pages read as raw markdown, model configuration 109,848
  bytes; effort 39,458 bytes). **Recheck trigger:** the calibration property being restated as
  cross-model-stable, a first-run effort hold returning to the model-config page, the resolution
  order or the `effortLevel` user-settings exemption for Opus 5.5 changing, or `high` ceasing to be
  the general default.

### I22: Model-routing doctrine with no baseline named

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** a surface stating **first-party model-selection or routing doctrine** that names
  neither a baseline for the reading it was derived from nor an event that re-opens it: a lane table
  ("wide reads to this model, mechanical fan-out to that one"), a "use model M for work of kind K"
  rule, a selection matrix restated from vendor pages. Model lineups, per-model guidance, and selection
  matrices are revised on every release, so lanes derived from one reading and written down without
  their provenance become a claim about a model generation that has since passed, told in the present
  tense.
- **Remediate:** name the baseline and the triggers, as the record parts beside the doctrine: a
  pointer to the vet or reading the lanes came from, its as-of date, and the observable events
  that re-open it: the pinned model changes, per-model guidance or
  its notes change, the selection-matrix rows change, a volatile figure a lane turns on drifts.
  **The action on a trigger is a targeted delta check against the named baseline, never a
  re-derivation from scratch.** That is what makes the trigger cheap enough to honor, and a trigger
  nobody can afford to run is not a control.
- **The consumer supplies its own baseline; this row carries none.** A catalog row naming a date or a
  vet would hand every consumer a foreign snapshot as their baseline, which is the precise drift this
  check exists to catch.
- **Must NOT flag: doctrine that ran no vet of its own.** A surface transcribing a named third
  party's stated practice, with author, source, and sync provenance recorded, has no baseline reading
  to name because it performed none. Flag first-party doctrine: lanes this surface's own authors
  chose. **This fence is narrower than it looks, and deliberately so.** A sync stamp tracks whether
  the *transcription* is current, not whether the transcribed advice still names a live model, so it
  does not make a stale lane recommendation fresh. The fence rests only on there being no vet to
  point at; the residual staleness is real and is the transcribing surface's to carry, not this
  row's to detect.
- **Must NOT flag: `model:` frontmatter and other configuration values**, on the same discriminator
  as I21 and I17. Those implement doctrine rather than stating it, and a config-mechanics finding
  belongs to `harness-config:audit`.
- **Must NOT flag: a pointer.** A surface routing the reader to the vendor's own selection page
  instead of restating lanes has nothing to go stale. Nor doctrine already carrying a baseline and
  triggers, whatever heading they sit under.
- **Why this is not I19, and not the catalog trigger.** I19 covers a restated *benchmark figure* and
  asks for the record parts; it says nothing about lane assignments and nothing about how to
  *act* when a trigger fires. The delta-not-re-run discipline is this row's own contribution. The
  catalog-wide recheck trigger does not reach it either: that trigger governs **this catalog's**
  staleness against its Sources, not an audited surface's staleness against the pages its doctrine
  was read from.
- **Source:** none. No official page states that model-routing doctrine must name a baseline and
  delta triggers, which is why this check is `OPINION`-tier and off by default, the same footing as
  I19, and it adds no Sources entry for the same reason. The record shape it asks for (a pointer to
  the baseline, an as-of date, observable recheck triggers beside the doctrine) is this monorepo's
  `docs/conventions/upstream-drift/README.md`; in a standalone install those parts, not the path,
  are the requirement.

### I23: Context-budget directive to stop, summarize, or hand off

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all · Model scope:
`fable-5, fable-5-1` (sourced from that guide alone; promotion gate unmet).

**The tier keys on the ground truth of the defect, not of the detection.** The phrasing is statically
readable, which tempts a `mechanical` tag, but I8-b's Detect is a literal three-phrase match and is
even seeded in the pre-scan, and it is `behavioral`. The `mechanical` rows rest on a documented hard
consequence: I10 on a refusal category the API returns, I21 on a property its page states outright.
This row rests on a reported model *tendency* (an occasional new-session suggestion), with no
documented hard consequence, which is the behavioral tier's definition. The stake is the Output
format rule: behavioral findings ship as proposals verified per Deletion tiers, never as
confident removals.

- **Detect:** instruction text directing the model to monitor its own remaining context and to stop,
  summarize, hand off, trim its work, or start a new session **on that basis**, and instruction text
  or injected hook output that surfaces a remaining-context count to the model where the surface
  could avoid it. The guide names the count as the usual trigger for the behavior, so the disclosure
  and the directive are one subject; it also hedges the disclosure arm, and this row tracks that
  hedge rather than reading it as an absolute.
- **The discriminator is who decides, on what evidence.** A directive tells the model to judge its
  own window and act; a mechanism resolves the window from an instrumented signal and acts itself.
  Only the first is this row's subject.
- **Must NOT flag: a mechanism that gates on a measured signal.** A hook, gate, or workflow step that
  reads context state from an instrumented source and then blocks or routes on it, or injects a
  determination the model does not re-decide, is not a directive to the model, and it outranks the
  model's own initiative rather than competing with it. **A hook that injects an exit menu remains
  this row's subject**, however well instrumented its trigger: the measurement decides only when to
  ask, and the model still decides whether to stop, so the injection manufactures the initiative
  rather than replacing it. The contrast that fixes the line is a `PreToolUse` deny. There the
  mechanism decides and the text is only the consequence. **The exemption never covers surfacing the
  count itself.** A determination is a resolved verdict the model consumes; a raw remaining-context
  number is data it must interpret, which is the disclosure arm of Detect and is a finding whoever
  computed it. Being measured makes a mechanism's *trigger* trustworthy, never its payload.
- **Must NOT flag: a user-invoked skill whose purpose is the continuation itself**: a handoff
  writer, a continuation router, a compaction helper. The skill existing is not an instruction to
  watch the budget; a skill body that additionally tells the model to invoke it off a self-estimated
  window is. **A router falling back to its own judgment when no measured signal is available is
  also not a finding.** It prefers the instrument and degrades only in its absence, which is the
  opposite of the shape this row detects.
- **Must NOT flag: a routing condition that selects between two forms of one deliverable.** "Use the
  short form where the full one would not fit" picks a shape; it does not stop the work. The subject
  is abandoning or truncating the work, never sizing an artifact to its container.
- **Must NOT flag: a budget surfaced to the human.** A status line, a report, or a cost dashboard
  renders to the operator rather than into the model's context, and no part of this row reaches it.
- **Must NOT flag: a document *about* the pattern**, such as this row, a model-adaptation delta
  chapter, or a verification record quoting it, on the audience test I8-b applies. **A playbook
  stating the counter-steer is exempt on different grounds, and the distinction matters:** that text
  is operative standing instruction, so I8-b's audience test would reach it rather than excuse it. It
  is not a finding because its **polarity is inverted**. It instructs the opposite of Detect, so it
  never satisfies Detect and needs no exemption at all.
- **Remediate:** remove the directive. Where the guarantee behind it is real, move it to a mechanism
  that gates on a measured signal, or state the counter-steer plainly: that a count alone is not a
  decay signal, because decay shows up in the output rather than in the number. Where the harness
  genuinely must surface a count, pair it with a reassurance rather than with an exit menu.
- **Which signals license a continuation, and which do not.** This is the calibration the row
  shipped without, and it is a policy rather than a regex. Three signals license a skill or surface
  to route into a handoff, a fork, or a new session: **the user's own report**, **an instrument that
  measures the window**, and **visible decay in the model's own output**: drift, repetition, dropped
  constraints. A **self-estimated budget is none of the three**, and a surface naming one as a
  trigger is a finding wherever it sits. The third signal is the one the model reads for itself, and
  it is legitimate precisely because it is the thing a count cannot see; a row that treated every
  model-side continuation trigger as a defect would refuse it too, and refuse the guide's own
  reasoning with it.
- **Residency is a severity input, not an admission test.** A trigger in a `description` is resident
  whenever the skill listing admits it, which is the default, since `disable-model-invocation: true`
  also suppresses the description from context (pointer:
  [Skills](https://code.claude.com/docs/en/skills#frontmatter-reference), as of 2026-08-08). A
  body-borne trigger costs context only once the skill loads, or at startup
  in a subagent with the skill preloaded. Both are findings; the resident one is the more expensive to
  leave. **Second-source recheck trigger:** that page's invocation-control table changing which
  fields keep a description in context, which would re-rank the two residencies and is the only fact
  this clause and the remediation below rest on.
- **Remediate by moving the trigger, never by withdrawing the skill.** Flipping continuation skills
  to `disable-model-invocation: true` is the considered alternative and is refused: it costs every
  model-side invocation the skill has, including the ones a user asks for in the words its
  description exists to match, to remove one clause. Removing the clause costs only the behavior
  the source counsels against.
- **Pre-scan seeded (`I23`).** A continuation skill can barely be model-invocable without naming a
  context trigger somewhere, and under the licensing rule above those triggers are true positives,
  not noise. **The pattern marks budget phrasing alone and
  never the verb it governs**, because the trigger and the action it licenses routinely sit in
  different sentences; the counter-steer text that forbids the behavior therefore matches too
  (inverted polarity, exempt), as do documents about the pattern and operator-facing budgets. That
  over-production is the same contract I8's families carry. It is deliberately **not** anchored to
  the bare term "context window", which is ordinary vocabulary in any surface discussing sessions and
  would return the corpus instead of a candidate set.
- **Source:** Fable 5 guide, "Rare cases of context-budget concern" (the behaviors, the
  remaining-token countdown as the usual trigger, and the hedged advice against surfacing counts).
- **As of 2026-08-08** (our probe: that guide read as raw markdown, 177 lines). **Verified
  negative, which is what holds the scope annotation on:** the Opus 5 guide (11,225 bytes) and the
  Sonnet 5 guide (15,864 bytes) were read as raw markdown the same day and searched for this
  claim. Neither states it. Opus 5's only mention of the context window is a capability statement
  about consistency across the window, which is the opposite subject: a reason the concern does
  not arise, not a counter-steer against it. **Recheck trigger:** a second model guide stating
  the claim, which would meet the
  promotion gate and unscope this row, or that section ceasing to name the remaining-token
  countdown as the trigger, which is what joins the disclosure arm to the directive arm.
- **Widened to `fable-5-1` on 2026-09-03**, first on the bundled `claude-api` skill's
  model-migration reference. That basis's trigger fired when the Fable 5.1 guide was published. The
  widening now rests on our reading of that guide on 2026-10-01 (read whole as raw markdown; no
  artifact stored): no section names a context-budget difference from Fable 5, so we keep the
  Fable 5 claim for `fable-5-1`. Pointer: [Prompting Claude Fable
  5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1),
  the text above its first heading, which carries no heading id on the rendered page, so the link
  is to the page. As of: 2026-10-01. Recheck trigger: the Fable 5.1 guide naming a context-budget
  difference from Fable 5, or its opening changing what it says about Fable 5 prompts.
- **Re-justified 2026-10-01 against the current models:** `fable-5` stays, since Fable 5 is a
  current model (see "Tokens of models that are no longer current"). The row does not widen to
  `sonnet-5-5`: a countdown after tool
  results on that target is I37's subject, and our probe of the Opus 5.5 and Sonnet 5.5 guides that
  day (each read whole as raw markdown; no artifact stored) found no statement of this row's claim.
  Pointer: [Prompting Claude Opus
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
  and [Prompting Claude Sonnet
  5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5),
  whole pages, since the probe is a negative over every section. As of: 2026-10-01. Recheck
  trigger: either guide states this row's claim, which meets the promotion gate.

### I24: Instruction relying on silent generalization

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all. Unscoped.
Promotion gate MET: two model guides state the identical claim (see Source).

- **Detect:** instruction text that demonstrates or names ONE instance while the author's evident
  intent is a whole class, with no explicit scope statement: text a literal-minded executor would
  satisfy by doing exactly the one instance and stopping. We treat current models as reading
  instructions literally, more so at lower effort: an instruction about one item is not carried to
  its siblings, and unstated requests are not inferred. Four shapes:
  1. **A worked example standing in for a rule**, "rename this field like so" meaning every such
     field, with no "apply to every / all / each" scope line.
  2. **An enumeration whose tail the executor must guess**: a list ended with "etc." or "and
     similar" where no class is named that decides membership.
  3. **A single item named inside an iterating procedure**, "fix the header" or "update the test",
     where the surrounding procedure plainly processes many.
  4. **A per-item step whose iteration is implied but never stated**: "check the frontmatter" in a
     skill that processes N files.
- **Remediate:** state the scope explicitly, as one line naming every item the instruction covers
  rather than only the first. Name the class an "etc." tail was standing in for; attach the
  iteration to the per-item step.
- **Must NOT flag:** an instruction whose single-instance reading is correct, because the request
  really is one item. Scope stated anywhere in reach of the instruction (a "for each X below" frame,
  a table iterated by contract, a stated general rule the example sits inside as a labeled example).
  An "etc." tail whose enumeration illustrates an explicitly named class ("destructive actions such
  as X, Y, etc.", where the class decides membership, not the tail). A document *about* the pattern,
  on the audience test I8-b applies.
- **The converse is not a finding.** Over-specifying scope wastes words but misleads no executor;
  trimming it is I1's or the compression lane's concern, never this row's. This row is additive. It
  proposes scope statements, so the Stopping condition's high-consequence withholding does not
  bind it: adding explicitness to a safety gate is safe where trimming one is not.
- **Source:** Sonnet 5 guide, "More literal instruction following", and Opus 4.8 guide, "More
  literal instruction following". The two sections state the same claim for their respective
  models, and both give the same remediation example.
- **As of 2026-08-08** (our probe of both guides as raw markdown; Sonnet 5: 15,864 bytes, MD5
  `6d23959f0ed226feb06bf20c314029e3`; Opus 4.8: 15,905 bytes, MD5
  `6b9db5b784ad6a7b2e6307c1481b8be9`). **Recheck trigger:** either guide ceasing to state the
  literalism claim, or a model guide stating that its model resumes generalizing instructions,
  which re-opens the scoping question rather than deleting the row.

### I25: Sampling parameter prescribed where the model rejects it

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. The severity is
`error` because following the instruction produces a rejected request, the same consequence class
as I17, I18 and I20. Unscoped. Promotion gate MET: the claim is stated on a model-agnostic feature
page (thinking, "Sampling parameters", the pointer under Detect), not only in model guides. **The
model range is a Detect condition, not a `Model scope` annotation**, for the reason I17 base
states.

- **Detect:** instruction text directing a reader to move `temperature`, `top_p`, or `top_k` off
  its default, commonly "raise the temperature" for variety, creativity, or design
  divergence, or "set `temperature = 0`" for determinism, where the run's resolved target model is
  in this row's set: Claude Opus 4.7 or later (Opus 4.7, Opus 4.8, Opus 5, Opus 5.5), Claude
  Sonnet 5 or later (Sonnet 5, Sonnet 5.5), Claude Fable 5.1, Claude Fable 5, Claude Mythos 5.1,
  Claude Mythos 5, or Claude Mythos Preview. Fire on those models whether or not the surface also
  sets thinking, and even where the instruction would type-check against an SDK. A model outside
  the set is outside this row, whatever it does with thinking on.
  Pointer: for the set, see [thinking: sampling
  parameters](https://platform.claude.com/docs/en/build-with-claude/thinking#sampling-parameters).
  As of: 2026-10-01. Recheck trigger: a model joins or leaves that section's list.
- **Remediate:** remove the parameter and steer tone and variety with system-prompt instructions
  instead. For design variety specifically, the propose-options pattern is the documented
  replacement (see I26). Where the prescription was `temperature = 0` for determinism, note that
  it did not guarantee identical outputs on prior models either.
- **Must NOT flag: a claim carrying its own model gate.** Text scoped to a pinned earlier model
  where the parameters are live is correct rather than stale. As in I17-c, **the finding is the
  missing gate, never the mention.** **The parameter expressed as an SDK request field, config
  value, or code sample** rather than prescribed in instruction text, which is a source-code or
  config-mechanics finding on the discriminator I17 base, I21 and I22 apply. **Non-sampling senses
  of the word**, such as body temperature, disk or thermal temperature, or color temperature, which
  share the token and nothing else. A document *about* the pattern, on the audience test I8-b
  applies.
- **Source:** thinking, "Sampling parameters" (the set and the gate, under Detect). The Fable and
  Mythos guide's section on migrating from Claude Opus 5 (under Sources) keeps the Fable/Mythos
  carry-over. Corroborated at the Claude Sonnet 5 model page and in the Sonnet 5 guide, "Tone and
  writing style", which supplies the Remediate line. Both are Sources entries.
  Pointer: [Claude Sonnet 5, good to
  know](https://platform.claude.com/docs/en/models/sonnet-5/overview#good-to-know) and
  [Sonnet 5 guide, tone and writing
  style](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5#tone-and-writing-style).
  As of: 2026-10-01 for the set and the corroborating pages; the determinism note under Remediate
  rests on our 2026-08-08 reading of a page no current page replaces. Recheck trigger: the
  rejecting model set moving, sampling parameters being reinstated on any model in it, or a docs
  page starting to cover the determinism note.

### I26: Generic negative steering on open-ended design briefs

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all. Unscoped.
Promotion gate MET: two model guides converge (see Source).

- **Detect:** operative instruction text steering visual design away from a model's default style
  with generic negatives or vague qualifiers (banning a color without naming its replacement,
  asking for "clean" or "minimal", "less corporate", "not generic") with neither a concrete
  specification nor a propose-options step. We treat such instructions as trading one default look
  for another default look, not as producing variety. Also flag text recommending sampling
  parameters as the design-variety mechanism, which additionally reaches I25 on an in-range target.
- **Remediate:** either of the two approaches both guides cover: (1) specify a concrete
  alternative, which the model follows precisely; or (2) have the model propose distinct visual
  directions first (each naming its colors and type with a short reason), have the
  user pick one, and implement only that, which is the recommended route to distinct directions
  across runs on Sonnet 5, where `temperature` is not accepted. A short anti-generic-aesthetics
  directive with concrete, enumerable negatives
  (named fonts, named schemes) is the guides' own sanctioned snippet shape, not a finding. Pair the
  exclusion list with an iteration step: look at what the output fell back to, and add those
  styles to the list when they are unwanted as well.
- **Must NOT flag:** concrete enumerable negatives. Naming the exact fonts, palettes, or patterns
  to avoid is the sanctioned shape, distinct from a vague qualifier. Non-design uses of "clean" /
  "minimal" (a clean audit, a minimal reproduction). A surface that already runs the propose-options
  pattern, which is the remediation present. A document *about* the pattern, on the audience test
  I8-b applies.
- **Source:** Sonnet 5 guide, "Design and frontend defaults", and Opus 4.8 guide, "Design and
  frontend defaults", convergent on the default-style behavior, the fixed-palette failure of
  generic instructions, and both remediations; the Sonnet 5 guide adds the temperature-is-gone
  ground for preferring propose-options. Third convergent guide: Opus 5.5, "Frontend design
  defaults" (the generic-look negative, named patterns, and the iteration step).
- **As of 2026-08-08** (our probe of both guides as raw markdown, hashes as in I24); the Opus 5.5
  guide as of 2026-09-23 (hash as in I8-c).
  **Recheck trigger:** either guide's design section dropping the fixed-palette claim or the
  propose-options recommendation.

### I27: Effort lowered to shorten the response

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all ·
Model scope: `opus-5` (both statements of the property are qualified to Claude Opus 5, the guide's
and the effort page's inside its Opus 5 section; no model-agnostic page states it, so the promotion
gate is unmet).

- **Detect:** instruction text directing a reader or model to lower effort TO SHORTEN the
  visible response, such as "lower effort to keep replies short" or "reduce effort so answers stay
  concise", the premise being that the effort level controls response length. Seeded by the
  scanner's I27 family (an effort-lowering directive and a brevity token on one line); the lane
  adjudicates that the line actually premises brevity on effort rather than merely co-locating the
  two.
- **Remediate:** replace the effort clause with an explicit length or style instruction, the
  documented control for response length, keeping any effort change only where its stated ground
  is thinking volume, cost, or latency.
- **Must NOT flag: effort lowered on thinking-volume, cost, or latency grounds**, since "reduce
  effort to cut thinking cost on mechanical work" states the property the docs confirm; this row
  fires only on the length premise.
- **Must NOT flag: response-length instructions themselves.** "Keep responses short" with no effort
  clause is the documented remediation, not the defect.
- **Must NOT flag: a document *about* the misconception**, such as this row, a model-delta chapter,
  or a verification record quoting the premise to refute it, on the audience test I8-b applies.
- **Must NOT flag: `effortLevel` settings keys and `effort:` frontmatter as such**, on the same
  discriminator as I21 and I17: a config value implements a choice without stating the premise;
  this row audits instruction text, including instruction text that lives in a config file.
- **Source:** Opus 5 prompting guide, "Response length and verbosity" (effort governs thinking
  volume, not response length, with a hedge). Corroborated by Effort, "Recommended effort levels
  for Claude
  Opus 5", which states it unhedged. The detection needs only the negative half (effort does not
  reliably shorten the response), which both pages state.
- **As of 2026-08-08** (our probe: the live guide raw-`.md`, 11,225 bytes, MD5
  `8579d63fc9f793784b8c56320fd74e71`, byte-identical to the 2026-07-25 corpus capture) and the
  effort page's Opus 5 section, both fetched that day. **Recheck trigger:** either page restating
  the property model-agnostically or a second model guide stating it (gate met → unscope), or
  either statement disappearing from its page.
- **Re-justified 2026-10-01 against the current models:** `opus-5` stays (see "Tokens of models
  that are no longer current"). We do not widen it. A model joins this row's scope only when its
  guide states that effort does not reliably shorten the response. On 2026-10-01 neither the Opus
  5.5 nor the Sonnet 5.5 effort section stated that. We read both as tying higher effort to longer
  output, which runs against this row's premise rather than with it, so widening to either model
  would flag a line its guide supports. Pointer: [Opus
  5.5 guide, calibrate
  effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#calibrate-effort)
  and [Sonnet 5.5 guide, calibrate
  effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#calibrate-effort).
  As of: 2026-10-01. Recheck trigger: either section starts stating that effort does not reliably
  shorten the response, or stops tying higher effort to longer output.

### I28: Over-aggressive trigger emphasis and blanket tool defaults

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all. Unscoped.
The claim sits on the model-agnostic best-practices page, its Migration considerations restate it
generation-wide (overtriggering on instructions written for earlier models), and no later model
guide reverses it; the Sonnet 5 and Opus 4.8 literalism sections corroborate the mechanism.

- **Detect:** two arms of one defect, prompting written against undertriggering that no longer
  exists:
  1. **Forced-compliance emphasis** on tool, skill, or behavior triggering, such as `CRITICAL:`,
     `You MUST use`, `IMPORTANT:`, or all-caps imperative runs, where the emphasis exists to make a
     trigger fire rather than to mark a genuine gate.
  2. **Blanket tool defaults**, such as "Default to using [tool]" or "If in doubt, use [tool]",
     where a targeted condition was the intent.
- **Must NOT flag: emphasis guarding a high-consequence area.** That is a safety gate, a
  destructive or irreversible action, a security or permission boundary, or an external contract,
  the same carve-out set the Stopping condition applies; a loud marker on the step where being
  wrong is expensive is design, not scar tissue. **Must NOT flag: a stated hard precondition.** An
  ordering an API genuinely requires ("resolve the ID first; the call fails without it") is a
  fact, however emphatically set. **Must NOT flag: a document *about* the pattern**, on the same
  audience test I8-b applies. This row is the canonical instance.
- **Remediate:** for arm 1, normal conditional phrasing: "Use this tool when …". For arm 2, replace
  the blanket default with the condition it was standing in for: "Use [tool] when <the condition
  the default stood in for>." Verify per Deletion tiers (a consequential removal needs a
  closed watch, an editorial one does not); watch for overtriggering receding, not just continued
  triggering.
- **Source:** prompting best practices, "Tool usage" (dialing back aggressive trigger language, with
  a worked example), "Overthinking and excessive thoroughness" (targeted instructions over blanket
  defaults), and "Migration considerations" (anti-laziness prompting).
- **As of 2026-08-08** (that page read as raw markdown). **Recheck trigger:** those
  three sections changing, or any model guide stating that a current model undertriggers and needs
  emphasis restored, which would re-open the scoping question.
- **That trigger fired on 2026-10-01, and the arms stand.** Two current guide sections on tool
  and search triggering (pointers below) were re-read that day; neither asks for emphasis or a
  blanket default back. So the row stays unscoped and keeps both arms, with one fence added:
  **Must NOT flag a search instruction scoped to a named class of facts**, even when it overrides
  the model's own judgment that no search is needed. That is a targeted condition, the arm-2
  remediation's own shape, not a blanket default; a line discouraging tool use is I36's.
  Pointer: [Sonnet 5.5 guide, tool use in
  chat and knowledge
  work](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tool-use-in-chat-and-knowledge-work)
  and [Fable 5.1 guide, search triggering at low
  effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#search-triggering-at-low-effort).
  As of: 2026-10-01. **Recheck trigger, restated:** a model guide asking for forced-compliance
  emphasis or a blanket tool default to be restored on a current model, which re-opens the scoping
  question; a guide describing under-triggering and prescribing a targeted condition does not.
- **Routes to the findings relay.** I28 and I29 (scanner-fed) and I30 to I33 (lane-fed, admitted
  through `--from-lane`) are the checks in this catalog whose findings reach `review:fanout`'s apply
  relay, behind `--persist-findings`. I28's two arms carry one
  crosswalk rule id each, `harness-config/audit-instructions/rule-coercive-emphasis` (arm 1) and
  `harness-config/audit-instructions/rule-blanket-tool-default` (arm 2), both `IMPORTANT`, argued in
  [the severity crosswalk](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md).
  Every other check here stays report-only: no crosswalk row, no relay. I32 relays as `error`
  (`CRITICAL`) on the marketplace arm and `warning` (`IMPORTANT`) on the user and project arm. The persist mechanics,
  including the body-scope fence, are [context/persist-findings.md](../context/persist-findings.md).
- **The remediation is a downgrade, never a deletion.** The directive survives verbatim and only
  its volume changes. A proposal that removes the instruction rather than its shouting has misread
  the check. The Source's own worked example drops a leading `CRITICAL: You MUST` and keeps the
  instruction, dropping only the shout.
  **One byte may legitimately differ: sentence-initial capitalization.** Where the emphasis is a
  *leading* wrapper, dropping it promotes the next word to sentence-initial position, so
  `…MUST resolve the item id` becomes `Resolve the item id`. That is forced by the edit, not a
  rewrite of the directive, and the Source's own example makes the same change (`use` → `Use`).
  Verbatim survival is therefore asserted **apart from that capitalization**; any other change to
  the directive's wording means the remediation overreached.
- **Body-scoped when it routes to the relay.** No emitted finding may carry a remediation that
  edits a `description`, a `when_to_use`, or a quoted `'trigger phrase'`:
  those fields are routing text, so such an edit is an auto-invocation regression rather than a
  debatable suggestion (the `skill-quality` plugin's `check-skill.sh` gate, where it runs, warns on
  a dropped trigger phrase against the base ref). A
  coercive phrase inside a description is still a real observation. It is reported to the human
  and never routed to the relay.
- **Scanner selection scope, deliberately narrower than the Detect prose.** Two forms the class
  covers are **not** mechanically selected, recorded here rather than left as a silent gap: a
  **whole bolded sentence** used as a shout, and a **general all-caps imperative run** beyond the
  fixed marker list. Both are too common in ordinary technical prose to select without a false-
  positive rate that would swamp the relay. Bold lead-ins are this repo's house style, and
  all-caps runs collide with acronyms, file names, and env vars. The model lane still judges them
  under this row; only the deterministic scanner withholds. Widening either is a calibration
  change that lands in the scanner with fixtures.

### I29: Body prose that restates the always-in-context description, or a sibling section

Tier `mechanical` · Authority `HOUSE` · Severity `warning` · Surfaces: skill bodies, agent
definitions, and any markdown file whose listing `description` is already in context. Unscoped.
The defect is session knowledge, not a model-era scar.

- **Detect:** two arms of one defect, body copy the model already has loaded:
  1. **Description-restatement**: an H2 section whose content is *wholly* recoverable from
     the file's own `description` (the capability sentence; the Use-when / Not-for tail is
     stripped before comparison so a trigger list cannot rescue or manufacture a finding).
  2. **Sibling-section-restatement**: an H2 section whose content is wholly recoverable from
     another H2 section of the same file.
- **Must NOT flag: partial overlap.** Most Purpose sections open with a sentence echoing the
  description and then add a failure mode, a path, or a threshold. Flagging the echo guts them.
  The finding keys on a section whose every content unit is recoverable; one unique content
  token is enough to stand the section down.
- **Must NOT flag: inline fencing.** A bolded `What tidy is NOT` sub-block inside `## Purpose`
  is the upstream inline pattern, not a standalone heading, and is not a section.
- **Must NOT flag: short orientation.** A section whose normalized text is under the scanner's
  length/token floor is a deliberate short restatement in a genuinely short skill, left to the
  model-graded lane. The mechanical scanner stays silent; the lane may still judge it.
- **Must NOT flag: footer / index headings as findings.** `## Cross-references`, `## Sources`,
  `## History`, `## External authority`, `## Recheck triggers` are sources for sibling
  comparison and are never themselves a restatement finding.
- **Remediate:** cut the body restatement. **Never** edit the `description`, `when_to_use`, or
  a quoted `'trigger phrase'`. The always-in-context field stays; only the body copy that
  restates it is removed. Verify by re-running `restatement-scan.py`. The heading should
  disappear from the candidate list.
- **Routes to the findings relay** behind `--persist-findings`, same producer contract as I28.
  The two arms carry one crosswalk rule id each,
  `harness-config/audit-instructions/rule-description-restatement` (arm 1) and
  `harness-config/audit-instructions/rule-sibling-restatement` (arm 2), both `IMPORTANT`.
- **Body-scoped when it routes to the relay.** The scanner never points at frontmatter. A
  description-level concern is reported to the human, never routed to the apply relay.

---

### I30: Dated verification stamp with no recheck trigger

Tier `mechanical` · Authority `HOUSE` · Severity `warning` · Surfaces: all. Unscoped. Generalizes
I19 from benchmark figures to every dated claim about a harness, a tool, an upstream page, or a
measurement.

- **Detect:** a claim carrying an as-of date ("verified 2026-07-13", "as of 2.1.240") but no
  observable event that would re-open it. The record is the decision, a pointer to the exact
  source section, an as-of date, and a recheck trigger beside the decision; a dated stamp that
  lacks the trigger is the finding, whether or not its pointer is present.
- **Must NOT flag:** a dated stamp whose trigger lives in a named owner record the site points at
  ("recheck per `reference/parent-contract.md`"); a CHANGELOG entry or ADR, which are history by
  design; a date that is data (a release date in a table) rather than a verification stamp.
- **Must NOT flag: a moving ref or an undated version literal** (`main`, a branch name, "requires
  2.1.200"). With no as-of date there is no stamp for this row to judge. When the evidence in hand
  shows the literal is stale, report it under [Out-of-catalog defects](#out-of-catalog-defects).
- **Remediate:** add the trigger as an observable event (a release note naming the flag, the
  pointed-at section changing the value the decision rests on, a version floor moving), or point
  the site at the dated owner record.

---

### I31: Migration-relative phrasing in skill bodies and the files they load

Tier `behavioral` · Authority `HOUSE` · Severity `warning` · Surfaces: a skill's `SKILL.md` and
every file it loads on invocation or reads on demand, such as `reference/`, `context/`,
`references/`, and `actions/` files, root-level spokes (`formats.md`), and per-slice
`<slice>/README.md` spokes; and a file a memory surface points the model at to read (e.g.
`~/.claude/references/*.md`). Unscoped. Every one of these loads into the model's context, so the
phrasing costs the same wherever it sits.

- **Detect:** "now works differently", "no longer", "also counts", "instead of the old", "since
  the change", and the like, describing a diff against a prompt or harness version the reader
  never saw.
- **Must NOT flag:** a structural contrast between two current alternatives ("separate body Bash
  calls rather than pre-compute lines" names two present mechanisms); a CHANGELOG or ADR; a dated
  record (pointer, as-of date, recheck trigger) whose trigger legitimately names the prior state.
- **Remediate:** state the current rule and its reason in the present tense; move the history to
  the CHANGELOG or an ADR.

---

### I32: Routing text that names a skill that does not resolve

Tier `mechanical` · Authority `HOUSE` · Severity `error` (marketplace arm), `warning` (user and
project arm) · Surfaces: descriptions, `Not for` and `Skip when` clauses, Boundary and Sibling
sections, any spoke that says "use `/<plugin>:<skill>`", and routing text on a user or project
surface (CLAUDE.md, a natively read AGENTS.md, rules, a user or project skill or agent).

- **Detect:** two arms.
  1. **Marketplace arm, `error`:** a `/<plugin>:<skill>` or `<plugin>:<skill>` reference whose
     target has no `plugins/<plugin>/skills/<skill>/SKILL.md`, or a routing sentence naming a
     plugin where a skill is required.
  2. **User and project arm, `warning`:** on a user or project surface, a routed skill name that
     resolves to no plugin, user, project, or nested skill directory and appears in no skill
     listing the run can see.
- **Evidence basis for arm 2:** the session's skill listing plus the plugin, user
  (`~/.claude/skills/`), project (`.claude/skills/`), and nested skill directories the inventory
  reached. The finding cites which of those it checked. It is a `warning` rather than an `error`
  because one session's listing is not every session's: a skill can be missing here and present
  where the surface is actually read.
- **Must NOT flag:** references to bundled Claude Code skills marked as bundled; a name that could
  be bundled, claude.ai-synced (an `anthropic-skills:` name, or a directory under
  `~/.claude/skills/synced/`), or gated by settings, environment, plan, or host, since none of
  those rosters can be enumerated from files; a capability named by class ("a visualization
  capability") that deliberately avoids a binding; a reference inside a fenced example.
- **Stamp:** we treat `anthropic-skills` as the namespace reserved for skills synced from
  claude.ai, and `~/.claude/skills/synced/` as their download directory. Pointer:
  <https://code.claude.com/docs/en/skills#when-a-synced-skill-name-matches-another-command> and
  <https://code.claude.com/docs/en/skills#where-synced-skills-load>. **As of 2026-09-27.**
  **Recheck trigger:** that page stops reserving the namespace or naming the directory, or a
  release note moves synced skills to another namespace or directory.
- **Remediate:** name the skill that exists, or describe the capability by class per the
  seam-phrasing convention; never leave a route to nowhere.

---

### I33: Sibling-file meta-commentary

Tier `behavioral` · Authority `HOUSE` · Severity `info` · Surfaces: every file a skill loads on
invocation or reads on demand other than its `SKILL.md`, such as `reference/`, `context/`,
`references/`, and `actions/` files, root-level spokes (`formats.md`), and per-slice
`<slice>/README.md` spokes; and a file a memory surface points the model at to read (e.g.
`~/.claude/references/*.md`).

- **Detect:** a spoke that opens by describing its own role and loading ("this file is read by
  step 3", "loaded when the skill runs in mode X", "the hub links here") rather than stating its
  content; the model reads a description of the file instead of the file.
- **Must NOT flag:** a one-line scope note that bounds the file's subject ("Windows only"); the
  hub's own index table, which is where loading conditions belong; frontmatter.
- **Remediate:** delete the self-description; keep the loading condition in the hub's index row.
- **Reporting:** one finding per spoke, anchored by an excerpt (`e:`) over the opener sentence, with
  its heading path as the duplicate discriminator. A whole-surface (`s:`) anchor survives this row's
  own remediation, so it never keys an I33 finding. I33 is lane-only (no pre-scan seed), and each
  lane brief restates the Must NOT flag fences above.

---

### I34: Maintainer rationale inside model-facing YAML comments

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: `SKILL.md` and
agent frontmatter, and any YAML block the model receives. A `#` comment in those surfaces is
loaded with the rest of the file, so a history narrative there is the same defect as one in a
skill body.

- **Detect:** a `#` comment in frontmatter or a model-loaded YAML block that justifies a value to
  maintainers ("kept at 5 because the old model rambled", "see PR 1234").
- **Must NOT flag:** a comment that states the current rule the value encodes ("cap is the
  working-memory budget"); comments in files the model never loads.
- **Remediate:** move the rationale to the CHANGELOG, an ADR, or a maintainer-facing `AGENTS.md`;
  leave the value and, at most, a present-tense reason.

---

### I35: Settled-answers instruction where later steps revise earlier ones

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all · Model scope:
`opus-5-5` (a single guide states the instruction and its limits; promotion gate unmet).

- **Detect:** an instruction telling the model to treat earlier answers as settled and not go back
  over them ("treat that answer as done", "don't revisit earlier answers"), on a surface that
  governs long analysis, investigation, review, or an agentic task where a later step can show an
  earlier one wrong.
- **Remediate:** remove it from that surface. Where a long-chat surface also carries it, keep it
  there only if the surface's work tolerates the model being less likely to point out its own
  earlier mistake.
- **Must NOT flag:** the instruction on a long-chat or project surface for short back-and-forth
  follow-ups, which is the shape the guide recommends; a document *about* the pattern, on the
  audience test I8-b applies.
- **Source:** Opus 5.5 guide, "Thinking instructions in chat system prompts" (where to leave the
  instruction out, and its cost to self-correction).
  **As of 2026-09-23** (our probe: the guide's raw `.md`, hash as in I8-c). **Recheck trigger:**
  that section dropping the carve-out, or a second model guide stating it.

### I36: Tool-discouraging language

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all · Model scope:
`sonnet-5-5` (a single guide states the claim; promotion gate unmet).

- **Detect:** a line that restricts tool or search use as a standing policy, naming no particular
  tool and giving no reason tied to one, or that ranks the model's recall above checking a source.
  The line must sit on a component that has, or hands work to an agent that has, a search or
  retrieval tool.
- **Remediate:** where the component's work depends on facts that change, propose replacing the
  line with the guide's form at the pointer; otherwise propose deleting it. That form is targeted,
  not a blanket default, so the replacement does not reach I28.
- **Must NOT flag:** a limit on one named tool that carries its own reason (side effects, cost, a
  rate limit, a slow or destructive tool), which is the surface's to set. I11's steering from an MCP
  tool to an equivalent CLI, which redirects tool use rather than discouraging it. A surface with
  no tool that could check a fact. A document *about* the pattern, on the audience test I8-b
  applies.
- **Adjacent rows:** I28 flags the opposite calibration, emphasis written to force a trigger; one
  line is never both. I17-d covers reduced tool reach with thinking off, on `sonnet-5`.
- **Source:** Sonnet 5.5 guide, "Tool use in chat and knowledge work". Pointer: [Sonnet 5.5 guide,
  tool use in chat and knowledge
  work](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tool-use-in-chat-and-knowledge-work).
  As of: 2026-10-01. Recheck trigger: a second model guide stating the claim, which meets the
  promotion gate and unscopes the row, or the section dropping it.

### I37: Harness text after every tool result

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all, chiefly hook
instruction text and text that configures a harness · Model scope: `sonnet-5-5` (a single guide
states the claim; promotion gate unmet).

- **Detect:** in an interactive session (one where the user can type while a turn runs), any
  configuration or instruction that adds model-visible text of any kind after every tool result
  without a condition. In Claude Code the
  mechanical form is a `PostToolUse` hook whose matcher covers every tool and which returns
  `additionalContext` on every call; elsewhere it is an instruction to a harness to append text on
  every step. For why the frequency matters, follow the pointer.
- **Remediate:** gate the text on the condition that needs the model's attention (a narrower
  matcher, a failure, a threshold) and delete any figure nothing acts on. For a harness built on
  the API, place the text as the pointer's section directs rather than as this row restates it.
- **Must NOT flag:** the API's own task-budget feature, which this row does not cover. A hook that
  fires on a narrow condition or only occasionally. A run where nobody can type mid-turn, such as a
  non-interactive `-p` run or an unattended lane. Hook output that reaches only the user, such as a
  status line or a transcript notice. A document *about* the pattern, on the audience test I8-b
  applies.
- **Adjacent rows:** I23 (scoped to Fable) covers a model deciding to stop or hand off on a budget
  it was shown; this row covers where and how often harness text lands. Their scopes do not
  overlap, so one countdown never draws both on one target.
- **Source:** Sonnet 5.5 guide, "Mid-turn user messages". Which hook output reaches the model is
  read from hooks, "PostToolUse decision control". Pointer: [Sonnet 5.5 guide, mid-turn user
  messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets)
  and [hooks: PostToolUse decision
  control](https://code.claude.com/docs/en/hooks#posttooluse-decision-control).
  As of: 2026-10-01. Recheck trigger: a second model guide covering the same topic, which meets
  the promotion gate and unscopes the row, or that section changing which kinds of per-step text
  it covers.

---

## Stopping condition

Authority `OPINION` · applies to I6 and I8 · **enabled by default**, opt out with
`--no-stopping-condition`.

Neither I6 nor I8 carries an a-priori bound: I6's only escape is a rewrite concession and I8's
remediation is unconditional, so both trim without a floor. This rule **withholds** findings rather
than emitting them, which is why it inverts the `OPINION` default above. Disabling it does not make
the audit more conservative, it removes the only bound on two trimming checks and makes both strictly
more aggressive.

- **Withhold** an I6 or I8 proposal where the instruction guards a high-consequence area: a safety
  gate, an irreversible or destructive action, a security or permission boundary, an external
  contract, or genuine ordering another step depends on. De-prescription is the default posture; it
  is not the posture in the places where being wrong is expensive.
- **Report every withholding** in the run's own section, naming the check it moderated and the
  ground. A silently suppressed finding reads as coverage.
- **Source:** none. A high-consequence carve-out appears on no official page, and it is the
  calibration knob the de-prescription guidance (I8's Fable 5 source) leaves unset.

---

## Out-of-catalog defects

No check id. This section admits a real factual defect a lane observed **incidentally**, with the
evidence already in hand, that no row's Detect and Surfaces fit: a stale version literal with no
as-of date, a wrong statement about what an operator's config file contains, a path that no longer
exists. It is not a search mandate. Lanes never hunt for general factual errors, and they never file
such a defect under the nearest row, since a row stretched to fit carries that row's severity and
remediation into a case its Detect never described.

- **Report** it in the skill body's Out-of-catalog subsection with Check `out-of-catalog`, the
  evidence that shows it false, and a proposed correction.
- **Verify** it in Phase C like any proposal, with its own refutation: reproduce the cited evidence,
  then ask whether the claim is false today. A defect whose evidence does not reproduce is dropped.
- **Route** it by class when an owner is installed: doc or config drift to a doc/config drift
  auditor, copied or stale upstream content to a provenance auditor, each named by class or with
  "when installed". With no such owner installed, the report here is the whole disposition.
- **Never relayed.** These rows are never written by `--persist-findings` and never reach
  `emit-findings.sh`.

---

## AGENTS.md content-home advisory

No check id, no severity, no Finding ID, no diff. Where the memory layer's content lives is not a
model-era question, so this is a routing note in the report's Routing subsection, never a row in the
findings table, and never relayed by `--persist-findings`.

- **Fires** under scope `all` or `claude-md`, once per tracked project file named `CLAUDE.md`,
  root or nested, outside any `.claude/`, `node_modules/`, `vendor/` or `.git/` tree, whose content
  is anything other than the single line `@AGENTS.md`. Those are the files migrate's plan covers.
  Phase A's records already hold the file. `.claude/CLAUDE.md` never fires: migrate does not plan
  it, and a shim there would import `../AGENTS.md`, not `@AGENTS.md`. `CLAUDE.local.md` and the
  user-scope `CLAUDE.md` never fire either: neither is a shared project file with an `AGENTS.md`
  counterpart. An upstream-owned or synced file routes to its owner per the Scope boundary instead.
  **Claim:** migrate's plan skips every path under those four trees. **Basis:**
  `instruction_dirs()` in `skills/migrate/scripts/plan-migration.sh` and `IP_EXCLUDED_TREES` in
  `scripts/lib/discover.sh`, both in the `instruction-placement` plugin. **As of:** 2026-10-01,
  instruction-placement 0.17.0. **Recheck:** when that plugin's CHANGELOG says migrate plans a new
  location.
- **Says**, per file:

  > `<path>` holds project instructions that could live in `AGENTS.md`, where other coding agents
  > read them too. Plan the move with `/instruction-placement:migrate plan`. Keep the `CLAUDE.md`
  > as the one-line `@AGENTS.md` shim: it is what loads `AGENTS.md` wherever a `CLAUDE.md` is read
  > instead, and in sessions that read no `AGENTS.md` at all. Migrate's `cutover-check` decides when
  > shims can come out; this audit never does. Claude-specific text goes to
  > `.claude/rules/<topic>.md` with a `paths:` glob, per migrate's routing.

- **Presence gate.** Name `/instruction-placement:migrate plan` when the `instruction-placement`
  plugin is installed. When it is not, the line names the same move (content to `AGENTS.md`, the
  `CLAUDE.md` kept as the `@AGENTS.md` shim) as a repository-wide change left to the operator.
- **Never** propose deleting a `CLAUDE.md`, emptying it, or removing its shim. When and whether a
  session reads `AGENTS.md` at all is recorded in
  [agents-md-liveness.md](../../../reference/agents-md-liveness.md); that record is why the shim
  stays.
- **Progressive disclosure is out of scope.** Whether the file should be split across load tiers is
  `/docs-hygiene:audit-progressive-disclosure` when the `docs-hygiene` plugin is installed; when it
  is not, the advisory notes the question as unjudged.

---

## Output format

Findings are presented using the Phase D report table defined in the skill body
([SKILL.md](../SKILL.md)), one proposed diff per finding. The column set lives there and is not
restated here.

A clean audit ("No instructions flagged.") is a valid outcome. Behavioral-tier proposals are
always presented as proposals verified per Deletion tiers, never as confident removals.
