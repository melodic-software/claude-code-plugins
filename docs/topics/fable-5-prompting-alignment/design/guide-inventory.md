# Fable 5 prompting guide — section inventory and adherence verdicts

Source: <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>

Captured 2026-08-08 from the raw-markdown channel (`…/prompting-claude-fable-5.md`, HTTP 200,
`text/markdown`, 177 lines, MDX artifacts intact). Every line of every paragraph was read from that
capture; the section IDs below (F0–F14) are this audit's units and appear nowhere upstream.

Pointer, not copy: this file records **what each section obliges** and **what already discharges
it**. It does not restate the guide. Read the guide for its own words.

## Population — what this audit is allowed to reach

**In scope: text that reaches a model as instruction at run time.** Skill bodies and their
`context/` and `reference/` chapters, agent definitions, command bodies, hook prompt text and any
hook output injected into context (`additionalContext`, `permissionDecisionReason`, Stop-hook
reasons), `prompts/**`, and this repository's own `CLAUDE.md` / `AGENTS.md`.

**Out of scope: text *about* plugins.** `README.md`, `CHANGELOG.md`, ADRs, and `docs/**` prose — a
document that discusses a pattern is not an instance of it, which is the audience test the audit
catalog already applies at I8-b, I8-d, I8-e, and I21. Where such a document restates model behavior
it is a fresh-docs concern (I12), not a Fable-adherence one.

## The additive bar

The guide's own §F14 says skills written for prior models are often **too prescriptive** for Fable 5
and can degrade output. Adherence is therefore substantially a removal exercise, and this audit
holds itself to the rule that follows from that:

> A finding that **adds** lines to a runtime instruction surface must state why default Fable 5
> behavior is insufficient, citing the guide section that says so. A finding that **deletes**
> over-enumeration needs no such justification.

Applied below: every `ADD` disposition carries its citation, and the audit produced no net addition
to any skill body.

## Scoping constraint inherited from this repository

[ADR-0006](../../../adr/0006-scope-model-doctrine-per-version-behind-a-promotion-gate.md) makes
doctrine sourced from a single model's guide **`Model scope: fable-5` by default**. Promotion to
fleet-wide happens only through the gate — a model-agnostic upstream page stating the claim, or a
second model guide converging on it. Everything sourced from this guide alone stays scoped.
[ADR-0007](../../../adr/0007-host-per-model-doctrine-outside-skill-private-surfaces.md) fixes the
per-model chapter address; this audit mints no new seam.

## Section inventory

Verdicts: `COVERED` (a surface already discharges it) · `MECHANISM` (discharged by a hook or gate
rather than by instruction text, which is stronger) · `GAP` (nothing discharges it) · `N/A`
(framing, or not an instruction-surface concern).

| § | What the section obliges | Doctrine side — `playbooks:fable-5` | Downstream side — `audit-instructions` catalog |
|---|---|---|---|
| F0 | Intro + Note: adaptive-thinking-only API surface; safety classifiers over offensive cybersecurity, biology/life sciences, and summarized-thinking extraction; configure fallback to Opus 4.8 | `SKILL.md:20` meta-rule 3 carries the classifier-fallback re-resolution rule, sourced to the system card | `N/A` — client fallback is harness configuration, not instruction content. I10 sources its scope from the same classifier set |
| F1 | Capability improvements over Opus 4.8 (long-horizon autonomy, first-shot correctness, vision, enterprise workflows, code review recall, ambiguity, delegation) | `N/A` — framing | `N/A` — framing |
| F2 | Longer turns by default; adjust client timeouts, streaming, progress indicators; act when you have enough information rather than overplanning | `SKILL.md:110` "end no turn on unexecuted intent"; `problem-framing.md` decide-or-ask ladder | `COVERED` — row **I8-d** (short-turn assumptions), `Model scope: fable-5`, sourced to this section verbatim |
| F3 | Effort is the primary dial; `high` default, `xhigh` for capability-sensitive, `medium`/`low` for routine; prevent unrequested tidying or refactoring at higher effort | `SKILL.md:25–34` "floors that survive every effort level"; `SKILL.md:83,86` scope fence and no-cleanup-around-a-fix | `COVERED` — row **I21** (effort pinned across a model change with no re-sweep), unscoped, gate met. Scope-creep half: see *Considered and declined* |
| F4 | Strong instruction following — one brief instruction replaces enumerating each behavior; brevity by selection not compression; pause only where the work genuinely requires the user | `SKILL.md:110` lead with the outcome; `SKILL.md:106` decide-or-ask ladder; `communication.md` | `COVERED` — row **I8 base**, `Model scope: fable-5`, sourced to this section's own "too prescriptive" claim |
| F5 | Ground progress claims — audit each claim against a tool result from this session; report outcomes faithfully | `SKILL.md:30,42,98`; `verification.md`; carried to other models at `reference/model-adaptation/opus-4-8.md:48` | `GAP` by design — an instruction to *add* grounding is advice, not a detectable defect. No row proposed |
| F6 | State the boundaries — when the user describes a problem, the deliverable is the assessment; check evidence before a state-changing command | `SKILL.md:105`, near-verbatim to the guide's block, including the unasked-artifact clause the guide names (drafted emails, defensive branches) | `GAP` by design — same reason as F5 |
| F7 | Parallel subagents — dispatch readily, communicate asynchronously, keep subagents long-lived | `SKILL.md:91–94`, including "dispatch is not a blocking call" | `COVERED` — row **I8 base**'s named worked instance is the delegation throttle, sourced to this section |
| F8 | Construct a memory system — one lesson per file, one-line summary, no duplication of what the repo already records | `SKILL.md:121` write every expensive conclusion to a durable note; `context-economy.md`. Adjacent plugin: `claude-memory` | `N/A` — memory-layer hygiene is `claude-memory:audit`'s surface by the catalog's own partition |
| F9 | Rare early stopping — a text-only statement of intent with no tool call, or asking permission when it already has enough; autonomous pipelines get a system reminder | `SKILL.md:110` "end no turn on unexecuted intent" | **`MECHANISM`** — `plugins/autonomy/hooks/lane-stop-gate.sh` intercepts the stop attempt itself and re-injects a completion self-check. A gate beats an admonition, and the guide's own remediation elsewhere prefers a mechanism to an instructed rhythm |
| F10 | Rare context-budget concern — avoid surfacing budget counts to the model; reassure if the harness must | `SKILL.md:124`, which states the counter-steer and then carves out "an instructed stop, or a workflow or mechanism built to gate on the window" under meta-rule 1 | **`GAP`** — no catalog row. A consumer's own surfaces can carry this shape and nothing detects it. **New row proposed: I23** |
| F11 | Give the reason, not only the request | `SKILL.md:61` because-clause restatement | `COVERED` — row **I7**, unscoped, promotion gate met by the model-agnostic best-practices page |
| F12 | Readability — drop working shorthand in the final summary; no arrow chains, hyphen-stacked compounds, or invented labels; write for a reader who saw none of it | `SKILL.md:110` "write the closing message for a reader who wasn't watching"; `communication.md` | **`GAP`** — no catalog row. A surface can *mandate* the shape the guide warns against. **New row proposed: I24** |
| F13 | Create a send-to-user tool — verbatim mid-turn delivery without ending the turn; pair with elicitation language or it is rarely called | `N/A` | `N/A` — a client-side tool definition in a host application. Claude Code plugins declare no such tool; the nearest native surfaces are file delivery and channels, and neither is this catalog's subject |
| F14.1 | Start at the top of your difficulty range | `N/A` — operator practice | `N/A` |
| F14.2 | Make self-verification explicit in long-run prompts; **separate fresh-context verifier subagents outperform self-critique** | `SKILL.md:101` — fresh-context verifier with binary criteria is a floor for multi-file work | `COVERED`, with a **recorded corroboration**: this is a second model guide agreeing with row **I8-a**'s independence carve-out. See *Corroboration* below |
| F14.3 | Refactor existing prompts and skills — prior-model scaffolding is too prescriptive | `N/A` — this is the audit's own instruction | `COVERED` — row **I8 base** cites this sentence as its source |
| F14.4 | Don't instruct the model to reproduce its reasoning — triggers `reasoning_extraction`, elevating fallbacks | `SKILL.md:21` meta-rule 4 forbids narrating compliance | `COVERED` — row **I10**, `Model scope: fable-5`, severity `error`, with a deterministic pre-scan |
| F14.5 | Create a send-to-user tool | `N/A` | `N/A` — same as F13 |

## This repository's own adherence — what was actually run

**Reasoning-echo (F14.4 / I10): clean.** The repository's own detector,
`plugins/claude-config/skills/audit-instructions/scripts/instruction-scan.sh`, was run over every
`skills/*/SKILL.md`, `agents/*.md`, `commands/*.md`, and `prompts/**` file, excluding `vendor/` and
`evals/`. Exactly one I10 candidate surfaced: `plugins/planning/skills/interview/SKILL.md:84`, which
reads "helping the **user** think out loud". The subject is the user, not the model's own reasoning,
so it is a scanner false positive of the kind the scanner's own header declares by contract
("over-production is by design"), not a finding.

**Short-turn cadence (F2 / I8-d): clean.** The only matches are in documents *about* the pattern —
`plugins/claude-config/CHANGELOG.md` and `plugins/playbooks/reference/model-adaptation/sonnet-5.md`
— which the catalog's audience test excludes.

**Conservative reporting (I8-b, unscoped so it fires on Fable 5 too): clean.** The single operative
match, `plugins/code-tidying/skills/tidy/reference/tidyings.md:102`, is the restraint-clause shape
that row I8-b names *by path* as its canonical non-finding.

**Context-budget disclosure (F10): one live instance, dispositioned below.**

## The one live instance — `context-guard`'s zone-crossing injection

`plugins/context-guard/hooks/zone-crossing-inject.sh:127` injects into the model's context, once per
worsening zone transition, a block naming the zone and then enumerating four continuation options —
continue, `/clear`, write a handoff and `/clear`, `/compact`. Those are precisely the three
behaviors F10 names ("suggest a new session, offer to summarize and hand off, or trim its own
work"), handed to a model the guide says is already predisposed to them.

**It is not a finding, and the reason is load-bearing.** F10's subject is the model's *unprompted*
initiative. `playbooks:fable-5` `SKILL.md:124` states the counter-steer and then carves out exactly
this case: "This governs your own initiative only — an instructed stop, or a workflow or mechanism
built to gate on the window, outranks it under meta-rule 1." The hook is such a mechanism: it
resolves the zone from a measured snapshot seam rather than from the model's self-estimate, fires
once per worsening transition rather than continuously, and its blocking sibling (`zone-gate.sh`) is
off by default. This is the same fence the catalog applies elsewhere to a constraint the surface
genuinely owns.

**A reassurance line was considered and rejected.** F10's second sentence is conditional — "If the
harness must show them, a reassurance helps" — and the antecedent is not cleanly met: F10 names a
**remaining-token countdown** as the trigger, and this hook surfaces a zone word, not a count. Adding
"you have ample context remaining" beside a block that still enumerates `/clear`, handoff, and
`/compact` would lengthen the injected text and read as a mixed signal rather than a reassurance. So
this audit makes **no edit to any runtime instruction surface**, and the additive-bar claim above
holds literally.

**What is left for `context-guard`'s own maintainers.** The injection fires on the first *worsening*
transition, which includes `smart → acceptable` — a zone the plugin's own vocabulary does not call
degraded — and hands a four-option exit menu there. Whether that menu belongs at `acceptable` or only
at `dumb` is a calibration question about the plugin's firing behavior, owned by that plugin, and is
recorded here and in the pull-request body as an observation rather than acted on. Changing a firing
threshold is a redesign, not an adherence fix.

## Corroboration recorded (F14.2)

Row **I8-a** (`Model scope: opus-5`) tells a surface to remove *instructed self-checks*, and carves
out architected independent review — a fresh-context reviewer blind to the producing rationale.
F14.2 is a second model guide reaching the same distinction from the other direction: it asks for
self-verification to be made explicit on long runs, and states that "separate, fresh-context
verifier subagents tend to outperform self-critique."

This does **not** move the promotion gate — I8-a's detection claim (that verification instructions
cause over-verification) is still stated by one guide only. What it does is remove an apparent
contradiction a future reader would otherwise have to resolve alone: Opus 5 says remove verification
instructions, Fable 5 says add them. Both are true because they name different things — self-critique
versus an independent verifier — and I8-a's carve-out is the line between them. The corroboration is
recorded in that row so the reconciliation is not re-derived.

## Considered and declined

**F3's scope-creep half gets no row.** The guide's counter-steer against unrequested tidying at
higher effort is real, but the detectable shape — "an instruction directing proactive cleanup beyond
task scope" — is the entire legitimate purpose of a tidying skill, and a row that fires on it would
be noise. The doctrine side already carries the fence (`SKILL.md:83,86`).

**F5 and F6 get no rows.** Both are instructions to *add* to a prompt. A catalog row detects a
defect in existing text; "this surface does not say X" is not a defect shape, and a row that fired
on every surface lacking a grounding clause would report the whole corpus.

**`docs/OFFICIAL-DOCS.md` is not extended.** That file's own charter scopes it to Claude Code's
documentation at `code.claude.com`, "relevant to authoring, distributing, or consuming plugins".
The model prompting guides live at `platform.claude.com` and describe model behavior, not harness
behavior. They are already indexed where they are used — the `## Sources` list in
`audit-instructions/reference/criteria.md`, and the per-chapter source lists under
`playbooks/reference/model-adaptation/` — which is pointer discipline working as intended. Adding a
second index would create a surface that drifts from those.

**No `fable-5.md` is added under `reference/model-adaptation/`.** ADR-0007 explains why that
directory holds chapters for models that are *not* Fable 5: Fable 5's doctrine is the twelve
`context/` chapters of the skill itself.
