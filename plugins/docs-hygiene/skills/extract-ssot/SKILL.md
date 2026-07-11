---
name: extract-ssot
description: "Deduplicate repeated markdown content — rule files, skill bodies, ADRs, docs — into a single named source of truth and migrate every call site to cite it by exact heading. Use when the same prose, literal, or concept appears (or is reworded) across 3+ files: 'DRY this prose', 'extract a shared rule', 'single source of truth for X', a value-bump diff touching 3+ files — refuses extraction below the Rule of Three."
argument-hint: "[identify|verify|plan|execute|batch|unwind] [<cluster-name>]"
user-invocable: true
disable-model-invocation: false
---

# Extract SSOT

## Why this skill exists

Codifies the markdown-SSOT-extraction pattern as a repeatable workflow. Each invocation targets ONE cluster of repeated markdown content and resolves it to a single named source of truth — consolidating into an existing SSOT home when one already owns the concept, otherwise creating a new artifact (e.g. a rule file or a new skill) — plus migration of all call sites to cite by exact heading.

The principle is the coding Rule of Three / DRY, applied to markdown text. If the same unit of prose appears 3+ times, changes together, and has an identity that can be named, collapse to one definition and reference by name. Below 3 instances, inline is the disciplined call — premature abstraction is the dominant failure mode.

Typical markdown extraction shapes the workflow handles:

- A vocabulary of CLI/API verbs that many prompts, skills, and rules invoke inline — collapsed into one rule file with stable headings the call sites cite
- A constraint or guardrail repeated across multiple skills (e.g. "always run X before Y") — promoted to a single always-loaded rule
- A workflow primitive appearing across several skills — extracted to a shared primitive doc that skills cite by name

Extraction is dangerous: ~19% failure rate even on curated skills (SkillsBench, n=84 tasks), ~50% on practitioner-authored skills (40-skill failure analysis). This skill encodes the guardrails (Rule of Three, categorical-shape test, ≤500-line bound, one-level-deep mandate, Metz unwind procedure) so each invocation is reversible and reviewable.

**Code / config escape-hatch.** Repeated string literals, magic constants, helper functions in source code, or repeated CI / settings / MCP stanzas in config files are also extractable in principle (Rule of Three applies). This skill flags such clusters during `identify` but does NOT ship a citation contract for them — the caller uses the language-idiomatic form (`import` / `using` / `source`, YAML anchor, JSON `$ref`, build-tool include) and language-aware refactoring tools (IDE rename, Roslyn / ts-morph). Markdown is the only file class with no language-level rename safety net — that is where the contract here adds value.

## Evidence discipline

Every extraction decision must be grounded in **direct evidence captured this session** — grep output or file reads you performed yourself. This skill calls such evidence **Tier 0**. Recall ("I remember seeing this repeated"), a subagent's survey summary, or any other synthesized claim is NOT Tier 0 — promote it via your own grep before it drives a plan or an edit. A subagent roster is a lead list, never proof.

## Scope: markdown SSOT

**In-scope:** repeated content across the consuming repository's tracked markdown — instruction files (`CLAUDE.md`, `AGENTS.md`, `README.md`), rule files (`.claude/rules/`), skill bodies (`.claude/skills/`), agent definitions (`.claude/agents/`), automation/routine prompts, ADRs, and docs. Markdown is the file class with no compiler or IDE refactor to catch a broken reference — the citation contract here is what closes that gap.

| Citation target | Form |
|-----------------|------|
| Rule-file H3 heading | `` per `<file>.md` "<exact heading>" `` |
| New skill | `/<skill-name>` invocation (skill internals NOT cited externally — see `/encapsulation-audit`) |

**Out-of-scope, but flagged during `identify`:**

- **Code clusters** (`.cs`, `.ts`, `.py`, `.sh`, `.ps1`, …) — repeated literal, magic constant, regex, helper function. Use language-idiomatic extraction (constants file, shared module, IDE rename refactor / Roslyn / ts-morph). Compiler + lint catch missed call sites — citation rot is structurally prevented.
- **Config clusters** (`.yml`, `.json`, `.toml`, `.editorconfig`) — repeated CI step, MCP entry, settings stanza. Use the tooling's native include / anchor / `$ref` mechanism. Schema validation catches mismatches.
- **Mixed clusters** spanning markdown + code + config — pick the canonical owner (usually code/schema where runtime authority lives), then each file class cites in its native form. This skill handles the markdown half; the code/config half follows that file class's own conventions.

The 6-test extraction gate (Rule of Three, namable, stable, self-contained, bounded, one level deep) generalizes to all file classes, and `context/decision-framework.md` annotates each test with code/config equivalents. The HOW (citation contract, rename sweep, encapsulation rule) is markdown-specific.

Boundary with single-file refactoring: a rename, inline, or extract confined to one file or one recent diff is ordinary editing, not this skill's job. `/extract-ssot` handles cross-file markdown deduplication where the repeated unit needs a stable name and cross-file citations. When work touches both, normalize the call sites first, then lift the named unit.

## When to use vs not use

**Use** when: 3+ instances of the same unit exist across files; the instances change together (correlated edits); the unit has a stable identity that can be named; the unit is self-contained (extracts cleanly without dragging unrelated context). **Normal-work entry point** — when a cleanup pass, audit, value-bump diff, or review surfaces ANY of the three duplication smells — (a) same literal repeated across 3+ tracked files, (b) value-bump diff touches 3+ unrelated files, (c) same concept reworded across 3+ files or contradicting nuance between files — route detection here. The skill accepts both literal and semantic clusters; the 6-test gate's "namable + categorical-shape + stable identity" tests admit semantic clusters provided the unit can be named and instances change together.

**Classify each file's role before flagging it as a duplicate:**

- **DESCRIBE** — the file IS the SSOT and owns the value or concept; keep the body.
- **USE** — the file consumes the concept as a load-bearing reference (rules, agent prompts, skill bodies invoking the rule); it MUST cite the SSOT by exact heading or path + key rather than restate body content.
- **EXPOSE** — the file surfaces the concept to humans for onboarding clarity (README install commands, error messages, public-facing docs); it MAY restate when onboarding clarity outweighs maintenance cost AND adjacent prose cross-references the SSOT.

Contract identifiers the SSOT defines (tier names, label slugs, action verbs, command names) stay inline in consumers — naming them is not duplication; those tokens ARE the contract surface. Content (definitions, criteria, mapping tables, thresholds, exception clauses) must cite, never recap.

**Don't use** for: single-file refactoring inside one diff; recent-diff simplification of a single skill or feature; filing a tracking issue (route to the repo's issue tracker); writing a new skill from scratch without an underlying repetition trigger (use a skill-authoring workflow such as the skill-creator plugin); cross-language type sharing where the answer is codegen, not text dedup.

Full decision matrix: `context/decision-framework.md` (6+5 checklist with worked examples).

## Action router

| Argument | Action | Purpose |
|----------|--------|---------|
| *(empty)* | Smart default | Auto-detect: working notes from a prior run hold an active candidate roster → resume the current phase; otherwise → `identify` |
| `identify [<cluster-name>]` | Find candidates (default = exhaustive subagent survey) | Dispatches a read-only exploration subagent over 30+ duplication heuristics (full body in `actions/identify.md`); ranks by ROI; emits batch-sequencing matrix + recommended `/extract-ssot batch` invocation. Refuses premature (<3 instances). Single-cluster mode (`identify <name>`) skips the subagent for a targeted Tier 0 grep |
| `verify <cluster-name>` | Refuse-fast pre-extraction gate | 6-gate cheap check (Tier 0 grep, citation state, primary-source URL gate, bifurcation check, off-by-one heuristic, LOW-ROI threshold). Output: `PROCEED \| REFUSE-{reason} \| WARN`. OPTIONAL — does not gate `plan`/`execute`. See `actions/verify.md` |
| `plan <cluster-name>` | Architect | Pre-step (Tier 0 grep): does an existing rule/doc already own the concept? If yes → consolidate-into-existing branch (extend the home + de-recap consumers, no new artifact). Else choose creation output type (rule vs skill); draft or extend SSOT body; sketch migration plan |
| `execute <cluster-name>` | Migrate | Write or extend the SSOT (skip writing when an existing home already documents the concept); rewrite call sites to cite + de-recap inline reproductions; sweep references via `/rename-references` if a heading/identifier changed; verify |
| `batch <cluster-list>` | Multi-candidate orchestration | Auto-`verify` filter, file-overlap matrix, sequential-by-default dispatch, lesson injection between subagents. See `actions/batch.md` |
| `unwind <ssot-name>` | Reverse | Re-introduce duplication per Sandi Metz wrong-abstraction recovery |

One action per response; actions don't chain implicitly.

## Decision framework

Before recommending extraction, run the 6-test gate (all must pass) + 5-test inline gate (any one keeps inline). Full checklist with evidence and worked examples in `context/decision-framework.md`.

Headline gate: **Rule of Three** (Don Roberts / Fowler) — refuse extraction at <3 instances. Premature abstraction is the dominant failure mode.

## Output type

Markdown branch (primary):

| Shape | Target | Trigger |
|-------|--------|---------|
| Concept already has an SSOT home | Consolidate into the existing file (extend it only where a consumer carries nuance the home lacks) + de-recap the inline reproductions; create no new artifact | An existing rule/skill/doc already owns the concept and consumers recap it inline instead of citing it. Positive output-type form of `verify` Gate 2 + anti-pattern Shape C; `identify` flags it as `edit-existing-rule` / `trim-to-citation` |
| Vocabulary, IF-THEN rules, hard constraints, ≤500 lines | Rule file wherever the consuming repository's own conventions place shared rules — default `.claude/rules/<topic>.md` (always-loaded) or a path-scoped rule file | Categorical markdown content; consumers cite by H3 heading |
| Workflow, multi-action, has its own actions/anti-patterns | New skill at `.claude/skills/<name>/SKILL.md`, authored via the consumer's skill-authoring workflow (e.g. the skill-creator plugin) | Process content; consumers invoke `/<name>` |
| New action on existing skill | Action row added to the skill's action router | The workflow maps cleanly onto an existing skill's concern — same domain, same triggers, same output surface — rather than warranting a new top-level skill |

Skill-vs-rule heuristic: if the SSOT body is mostly nouns (named units the caller cites), it's a rule file. If the SSOT body is mostly verbs (steps the caller invokes), it's a skill.

Non-markdown escape (out of scope for this skill's HOW; flag during `identify`, refer the caller to language-idiomatic tooling): code constants / shared modules / helper libraries; config includes / YAML anchors / JSON `$ref`. See `context/decision-framework.md` "Output type: rule file vs skill" for the fuller table including code/config rows and worked examples; this section is the canonical markdown summary.

## Citation form

For markdown call sites, cite by exact H3 heading text + 1-line inline summary. Template:

```text
<scope phrase> per `<rule-file>.md` "<exact heading text>".
<scope phrase> per `<rule-file>.md` "<exact heading text>" — <optional ≤80-char summary>.
```

For code call sites, use the language's native import syntax. For config call sites, use the tooling's native include / anchor / `$ref` mechanism.

One level deep — never chain `A.md` → `B.md` → `C.md`. A heading rename triggers a `/rename-references` sweep across all 10 syntactic forms.

Full contract incl. line-wrap edge case: `context/citation-form.md`.

## Encapsulation rule

Encapsulation enforcement (detection grep, public/private surface matrix, remediation paths) lives in its own skill — `/encapsulation-audit`. Different concern from duplication: violations are single-instance matters (Rule of Three does not gate them).

`/extract-ssot execute` invokes `/encapsulation-audit detect` during the refactor pass to catch any encapsulation violations introduced or exposed by the migration. See `/encapsulation-audit` for the public surface matrix, filter taxonomy, and remediation paths.

## Anti-patterns guarded

13-pattern taxonomy with mitigations: citation rot, over-indirection, leaky abstraction, loss of locality, reference resolution failure, wrong abstraction, premature extraction, self-generated SSOT, cache invalidation cascade, encapsulation violation, source-of-truth bifurcation, primary-source citation gate, Shape C dedup-by-deletion (positive). Each pattern + symptom + mitigation procedure: `context/anti-patterns.md`.

Patterns #11/#12/#13 derive from the empirical lessons in `context/lessons.md` and are surfaced as REFUSE triggers in the `verify` action.

The `unwind` action implements Metz's 3-step recovery for the wrong-abstraction case (re-introduce → keep used subset → delete unneeded → re-isolate).

## Phases per invocation

```text
identify-cluster → architect-plan → execute-migration → sweep-references → verify
```

For multi-session work, persist the candidate roster, plan, and per-phase status to working notes in the consuming repository (wherever its conventions put task notes) so a fresh session can resume from durable state instead of re-deriving it. End each phase with a short status entry: what's done, what's next.

Per-phase checklist: `context/execution-checklist.md`.

## Sanity checks

| When | Check | Evidence |
|------|-------|----------|
| Pre-extraction | 3+ instances confirmed via grep (Tier 0) | Grep output captured in the plan/working notes |
| Pre-extraction | Cluster has stable identity that can be named; instances change together | Decision-framework checklist marked in the plan |
| Pre-extraction | File-class scope identified (markdown / code / config / mixed) | Listed in the plan; citation form chosen per class |
| Per-callsite | Citation/import in the form native to the call site's file class | Diff review |
| Post-extraction | All 10 `/rename-references` patterns swept (markdown call sites) | Skill output |
| Post-extraction | SSOT reads sensibly in isolation (leaky-abstraction self-test) | Manual read |
| Post-extraction | Lint clean across affected file classes; cross-references and imports resolve | Linter/build output |

## What this skill does NOT do

- Decide for the user whether to migrate a specific cluster (advisory; user picks)
- Modify files outside the repository it runs in
- Skip per-phase user diff review
- Single-file micro-refactoring (rename, inline, extract confined to one file) — ordinary editing
- Workitem filing — route to the repo's issue tracker
- Author a brand-new skill from scratch without a repetition trigger — use a skill-authoring workflow (e.g. the skill-creator plugin)
- Cross-language type sharing where the answer is codegen, not text dedup
- **Replace a workspace-wide verification pass** — the `verify` action here is a per-cluster refuse-fast pre-extraction gate, not a build+test+lint run; run the consuming repository's own verification after `execute`

## Cross-references

- `context/decision-framework.md` — 6+5 gate, Pre-extraction Tier 0 checklist, output-type table, worked examples
- `context/citation-form.md` — full citation contract for markdown call sites
- `context/anti-patterns.md` — 13-pattern taxonomy with mitigations
- `context/execution-checklist.md` — per-phase checks for the `execute` action
- `context/lessons.md` — append-only empirical lessons from batch executions; consumed by the `verify` action and `context/decision-framework.md`
- `actions/identify.md`, `actions/verify.md`, `actions/batch.md` — action bodies (private surface)
- `/rename-references` — load-bearing 10-pattern sweep after any heading change (owns the syntactic-form set)
- `/encapsulation-audit` — encapsulation detection + remediation (separate concern)

## Recheck triggers

| Condition | Action |
|-----------|--------|
| External tool/CLI/API documented inside an SSOT rule ships a major version bump | Re-verify the Tier 0 flag/verb set in the affected rule file; cited entries may have moved or renamed |
| `/rename-references` adds a new syntactic form to its 10-pattern sweep | Update the sweep step in `context/execution-checklist.md` |
| Anthropic ships a first-class native rule/skill linker (heading-rename auto-sweep) | Demote the `/rename-references` step to advisory; reduce sweep scope |
| Practitioner-authored skill failure rate drops below 20% (SkillsBench refresh) | Reduce gate strictness; consider relaxing Rule of Three to Two for low-risk vocabulary |
