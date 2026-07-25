# S11 — "Applying this to your context → Skills"

Source text owned by this section (`source-article.md:104-109`), quoted whole so the claim split below
is auditable:

> **Skills**
> Think of skills as lightweight guides to let Claude find information when needed. Avoid making them
> overconstrained, except in highly important areas.
>
> For long skills, try and use progressive disclosure as much as possible- divide it into many files and
> split them out.
>
> It's best when skills encode particular opinions, knowledge, or best practices that are particular to
> you, your team, or product.

## Claims

1. **Skills are lightweight guides, not payloads.** "Think of skills as lightweight guides to let Claude
   find information when needed."
2. **Avoid overconstraining.** "Avoid making them overconstrained…"
3. **Carve-out for important areas.** "…except in highly important areas." (Kept separate from claim 2
   deliberately: claim 2 is the rule, claim 3 is the exception, and reconciling them is this section's
   deliverable. Merging them would hide the tension.)
4. **Progressive disclosure for long skills.** "For long skills, try and use progressive disclosure as
   much as possible- divide it into many files and split them out."
5. **Skills should encode particular opinions.** "It's best when skills encode particular opinions,
   knowledge, or best practices that are particular to you, your team, or product."

## Evidence status

All URLs fetched this session (2026-07-24).

| # | Status | Basis |
|---|---|---|
| 1 | **CONFIRMED** | <https://code.claude.com/docs/en/skills>: "a skill's body loads only when it's used, so long reference material costs almost nothing until you need it." Best-practices adds the SKILL.md-as-table-of-contents framing: "SKILL.md serves as an overview that points Claude to detailed materials as needed, like a table of contents in an onboarding guide." **Materially qualified** — see conflict C1: the *body* is lazy, the *description* is not. |
| 2 | **PARTIAL** | Official docs never say "avoid overconstraining" as a general rule. They frame it as a two-sided fit judgment, not a one-directional trim: "Match the level of specificity to the task's fragility and variability." High freedom is prescribed only "when multiple approaches are valid / decisions depend on context / heuristics guide the approach" (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>). The article's unidirectional phrasing is stronger than anything official. |
| 3 | **CONFIRMED, and official docs are far more operational than the article** | Same page defines **low freedom** — "Use when: Operations are fragile and error-prone / Consistency is critical / A specific sequence must be followed", with the analogy "Narrow bridge with cliffs on both sides: There's only one safe way forward. Provide specific guardrails and exact instructions." Also names the high-stakes trigger set explicitly: "**When to use:** Batch operations, destructive changes, complex validation rules, high-stakes operations." This is the decidable content the article's four words gesture at. |
| 4 | **CONFIRMED** | "Keep SKILL.md body under 500 lines for optimal performance / Split content into separate files when approaching this limit." Plus two constraints the article omits and that bound "divide it into many files": "**Keep references one level deep from SKILL.md**" (nested refs cause partial `head -100` reads), and "For reference files longer than 100 lines, include a table of contents at the top." |
| 5 | **CONFIRMED** | Best-practices' whole skill-creation method is elicitation of the user's own particulars: "identify what context you provided that would be useful for similar future tasks… Include the table schemas, naming conventions, and the rule about filtering test accounts." And the conciseness rule's converse: "Only add context Claude doesn't already have" — i.e. what earns its place is precisely what is particular to you. |

## The carve-out, defined operationally

Claims 2 and 3 are in tension, and an "avoid overconstraint" pass applied without claim 3 strips exactly
what claim 5 says makes a skill worth having. The article gives no test for "highly important." This one
is keyed entirely to observables a reader who did not write the skill can read off its body and
frontmatter, and it composes official "degrees of freedom" with this repo's own already-documented verb
contract (`docs/PLUGIN-PHILOSOPHY.md:50-56`).

**The five questions:**

1. **Mutates state outside the conversation?** Writes files, git refs, remote state, an external service.
2. **Irreversible without user help?** Deletion, force-push, merge, publish, send — no in-agent undo.
3. **Outward-facing / third-party-visible?** Push, PR, comment, publish, transmit.
4. **Sequence-dependent?** Skipping an earlier step silently produces wrong output later rather than an
   error (official: "A specific sequence must be followed").
5. **Irreplaceable data in blast radius?** Secrets, credentials, user-generated `data/`, unpushed work.

**Scoring:** two or more "yes" → **highly important**; tight constraint is correct and stays, and its
removal is a regression. Zero "yes" → **relax candidate**; absolute directives need a stated reason or
they go. Exactly one "yes" → author's judgment, not an audit finding.

This deliberately does **not** ask "is this skill important to the user" (undecidable by a non-author)
and does not ask about token cost (a different axis). It also inherits the repo's verb table for free:
`clean`/`tidy`/`fix`/`commit`/`setup`/`update` score ≥2 almost by definition, while `audit`/`scan` are
contractually read-only and score 0 on bare invocation.

**Second gate — the relax rule.** Even at zero "yes", a constraint is *not* strippable merely for being
absolute. Strip only if it also fails this test: **does the directive encode a particular opinion,
knowledge, or practice (claim 5), or is it generic advice Claude already has?** "Never invent a recipient
to justify the artifact" (`plugins/planning/skills/questionnaire/SKILL.md:23`) is absolute, scores 0 on
stakes, and is *keepable* — it is a hard-won product opinion. "Always read the file before editing it" in
a low-stakes skill is neither. This gate is what stops claim 2 from eating claim 5.

## Criteria

**C-1 — Constraint proportionality (SKILL.md body).**
Observable: run the five questions. If score is 0 **and** an absolute directive (`MUST`/`NEVER`/`ALWAYS`/
`Do not`) fails the relax rule's opinion test, flag as overconstrained.
Must NOT flag: `plugins/planning/skills/questionnaire/SKILL.md:23,33` — "Never invent a recipient", "Never
write the questionnaire to the working directory or a tracked path". Score is 0–1, but both encode
particular opinions (the second is a PII-out-of-git-history rule), so the relax rule protects them.

**C-2 — Gate presence where stakes are high (SKILL.md body).**
Observable: a skill scoring ≥2 must state, in its own body, (a) a preview/dry-run or read-only check step
before mutation, (b) an explicit user-confirmation point, and (c) an idempotency / preserve-unrelated
statement. Absence of any one is *underspecified where the area is important*. For `setup` skills this is
not inference — `docs/PLUGIN-PHILOSOPHY.md:238-244` already requires "idempotent and safe to rerun",
"transparent about what it inferred, changed, skipped", "safe for existing files, preserving unrelated
user content". A setup body silently omitting these fails the repo's own contract.
Must NOT flag: `plugins/source-control/skills/babysit-prs/SKILL.md` and
`plugins/work-items/skills/work-loop/SKILL.md`. Both carry gates in non-standard vocabulary
("deterministic merge gate", "fail-closed", "NEVER merges", explicit tier opt-in) — a keyword screen
false-negatives them. C-2 is a **read**, never a grep.

**C-3 — Progressive-disclosure structure (skill directory).**
Observable: body >200 lines with no `context/`, `reference/`, or `references/` sibling → split candidate.
Additionally, per official docs: reference files must be linked **one level deep from SKILL.md**, and any
reference file >100 lines needs a table of contents.
Must NOT flag: a 250-line body that is genuinely one indivisible procedure with no separable reference
material — splitting it would create the nested-reference partial-read failure the docs warn about.

**C-4 — Always-on listing cost (skill frontmatter `description` + `when_to_use`).**
Observable: combined length per skill against the 1,536-char Claude Code cap, and the **fleet total**
against the listing budget. This is the only skill surface with unconditional cost.
Must NOT flag: a long description that is long because it carries distinguishing trigger keywords — the
docs warn that overflow "can strip the keywords Claude needs to match your request", so trimming keywords
to save budget is the failure mode, not the fix.

## Targets in this repo

Every number below is from a command run in `D:/repos/.worktrees/context-engineering-rightsizing`.

**Population.** `find plugins -type f -name SKILL.md | wc -l` → **187**. Of these,
`find plugins -type f -path '*/vendor/*' -name SKILL.md` → **6**, leaving **181** authored skills.
The six vendor materializations, confirmed by that command and excluded from every figure in this file:

- `plugins/context7/skills/lookup/vendor/cli/SKILL.md`
- `plugins/context7/skills/lookup/vendor/find-docs/SKILL.md`
- `plugins/dometrain/skills/sync/vendor/SKILL.md`
- `plugins/playbooks/skills/boris/vendor/SKILL.md`
- `plugins/playbooks/skills/skill-authoring/vendor/SKILL.md`
- `plugins/playwright/skills/playwright/vendor/SKILL.md`

I also checked whether vendor is the *only* don't-hand-edit class: `scripts/cross-plugin-source-registry.txt`
lists three shared-source clusters (`hooks/hook-utils.sh`, `reference/artifact-protocol.md`,
`reference/standards-contract.md`) and `grep -c "SKILL.md"` on it returns **0**. No SKILL.md is
shared-source. Vendor is the complete exclusion set.

**Body-size distribution** (181 files): sum 25,370 lines, mean 140, min 34, p25 88, median 120, p75 172,
p90 225, max 499 (`plugins/source-control/skills/babysit-prs/SKILL.md`).
**Not one skill exceeds the official 500-line guidance.** The fleet is already compliant with claim 4's
mechanical half.

**Disclosure subtrees:** 73 of 181 have `context/`, `reference/`, or `references/`; 108 do not. Counting
any non-`evals` subdirectory: 83 with, 98 without.

**C-3 split candidates** — body strictly >200 lines (the repo's own soft cap) with no disclosure
subtree. Count verified by command: **7**.

| Lines | Path |
|---|---|
| 360 | `plugins/source-control/skills/babysit-loop/SKILL.md` |
| 301 | `plugins/work-items/skills/setup/SKILL.md` |
| 283 | `plugins/work-items/skills/work-loop/SKILL.md` |
| 266 | `plugins/source-control/skills/commit/SKILL.md` |
| 230 | `plugins/adhd/skills/clarify/SKILL.md` |
| 225 | `plugins/planning/skills/devils-advocate/SKILL.md` |
| 212 | `plugins/work-items/skills/work/SKILL.md` |

Four more sit just at or under the soft cap with no disclosure subtree and would cross it on any
material addition — `plugins/re-anchor/skills/sweep-all-disciplines/SKILL.md` (200),
`plugins/planning/skills/design/SKILL.md` (200), `plugins/adhd/skills/shape/SKILL.md` (198),
`plugins/education/skills/quiz-me/SKILL.md` (196). They are watch-list, not findings.

**C-4, the highest-leverage target.** Measured with a frontmatter parser that follows block scalars and
multi-line values and strips surrounding quotes (scratchpad `desc-sum.js`), summing the two fields C-4's
cap actually governs — `description` + `when_to_use` — across all 181 authored skills:
**104,971 characters always-on, mean 580/skill** (`description` alone: 104,760). No skill's description
spans multiple lines, and **zero of 181 breach the 1,536-char Claude Code cap** — the per-skill gate is
clean; the problem is purely the aggregate. Seven exceed 1,024 chars, topped by
`plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3` at 1,161.

Official mechanics, fetched this session (<https://code.claude.com/docs/en/skills>): "Claude Code loads a
listing of skill names and descriptions into context… The budget scales at 1% of the model's context
window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke
least, so the skills you use most keep their full text."

And the load-bearing constraint for a **marketplace** specifically, quoted verbatim: "**Plugin skills are
not affected by `skillOverrides`. Manage those through `/plugin` instead.**" The consumer-side
`name-only` trim documented as the standard remedy **does not apply to anything this repository ships**.
A consumer's only levers are raising the budget (paid every turn) or disabling whole plugins. The one
lever that lives with the author is description length at the source. The repo is partially aware —
`plugins/claude-config/skills/audit/SKILL.md:119` runs a Category G listing-budget check, and
`docs/MIGRATION-PLAYBOOK.md:78` already records the `skillOverrides` exclusion — but that audit inspects
a *consumer's* installed config; nothing gates the marketplace's own aggregate contribution.

**Overconstraint (C-1): no fleet-wide problem found, and I checked before concluding.** Absolute-imperative
density per 100 lines is low across the fleet; the top hits are `plugins/miro/skills/setup` (14.3),
`plugins/bug-report/skills/setup` (13.0), `plugins/dometrain/skills/setup` (9.6) — all `setup` skills,
i.e. skills scoring ≥2 on the five questions, where the constraint is *correct*. I hand-read the two
strongest low-stakes candidates the metric surfaced: `plugins/planning/skills/questionnaire/SKILL.md`
(47 lines) proved to be a well-shaped guide whose absolutes are protected by the relax rule, and
`plugins/repo-hygiene/skills/clean/SKILL.md` (175 lines) is the fleet's **positive control** — heavy
constraint ("Mandatory gate", "Never `--apply` on first invocation", a full risk/confirmation matrix) on
a skill scoring 5/5, combined with heavy progressive disclosure into `context/` and `reference/`. It is
claims 2–5 done correctly and simultaneously. **I did not find a defensible general relax target.**

**C-2 findings.** A three-observable screen over the mutating-verb population, then hand-verified.
`plugins/dometrain/skills/sync/SKILL.md` (56 lines) states none of the three; it is a thin
vendor-refresh skill that mutates a tracked materialization. `plugins/re-anchor/skills/setup/SKILL.md`
and `plugins/dometrain/skills/setup/SKILL.md` state a check step but no explicit preserve-unrelated /
idempotency guarantee, against the philosophy's setup contract. These are the genuine
underspecified-where-important candidates — a short list, and I am reporting it as short rather than
padding it.

## Conflicts and ambiguity

**C1 — Claim 1 is false on the surface that costs the most, and this is the section's sharpest conflict.**
"Lightweight guides to let Claude find information when needed" describes the SKILL.md *body*, which is
genuinely lazy-loaded. It does **not** describe the `description`, which is preloaded for every skill in
every session. This repo's aggregate is ~105k chars of unconditionally-resident text, and because
`skillOverrides` cannot touch plugin skills, a consumer cannot opt out per skill. Read naively, claim 1
licenses adding skills freely because they "cost nothing until needed" — for a 181-skill marketplace that
is precisely wrong, and the article never mentions the listing budget at all. The article's own
progressive-disclosure principle applied honestly to skills implies a *skill-count* discipline it does
not state.

**C2 — Official documentation prescribes the opposite remedy to claim 2, on the same page that confirms
claim 3.** Best-practices' iteration loop advises, when Claude misses a rule, "using stronger language
such as 'MUST filter' instead of 'always filter'." It also devotes a full "Examples pattern" section to
input/output pairs ("Examples convey the desired style and level of detail to Claude more clearly than
descriptions alone") — which the article contradicts in its own "Then: Give Claude examples / Now: Design
interfaces" turn. Both were fetched this session. This is not a stale-doc artifact; it is a live
disagreement between the article and current official guidance, and any rightsizing pass in this repo
will hit it. The article is one Anthropic engineer's model-specific guidance for Claude 5; the
best-practices page is cross-model and explicitly says "What works perfectly for Opus might need more
detail for Haiku."

**C3 — A naive relax pass would strip a deliberate, documented repo mandate.**
`docs/PLUGIN-PHILOSOPHY.md:396-406` requires that "a skill step whose output judges work produced in the
same context delegates that judgment to a fresh-context (non-fork) subagent — **Mandatory in the skill's
design, not left to the invoker to remember**." That is textbook overconstraint by claim 2's letter, and
it is correct: it exists because "a context that produced work is structurally the weakest place to judge
that work." It is also load-bearing for the user's global instruction that producer ≠ critic ≠ tester.
The five-question test scores fresh-eyes sites low on *state mutation*, which is why the relax rule's
opinion test — not the stakes score alone — is what protects it. Any pass applying claim 2 mechanically
strips it.

**C4 — Claim 4 is already implemented here; the finding is "no new rule needed."**
`plugins/skill-quality/scripts/check-skill.sh:133-134` sets `LINE_HARD_CAP=500` and `LINE_SOFT_CAP=200`,
erroring at the hard cap and warning at the soft one with "consider pushing detail to
progressive-disclosure spokes." Zero of 181 skills breach 500. Adopting claim 4 as a new criterion would
duplicate a shipped, enforced gate. The residual value is C-3's *structural* half (the 11 skills above
200 with nowhere to split into) and the two official constraints the repo does **not** currently
enforce: one-level-deep references and TOC-for->100-line reference files.

**C5 — Cross-surface description cap, stated precisely to avoid a false defect.** The Claude Code cap is
**1,536** chars for `description` + `when_to_use` combined (<https://code.claude.com/docs/en/skills>,
configurable via `skillListingMaxDescChars`), and `check-skill.sh:132` matches it exactly. The **1,024**
limit is the Agent Skills / platform API surface
(<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>). The 7 skills over
1,024 are therefore **not** Claude Code defects. They are a portability question only, and only if this
marketplace ever targets the API skills surface — `docs/PLUGIN-PHILOSOPHY.md:463-464` does treat the
Agent Skills specification as authoritative for the `name` field, so the two-surface question is live
rather than hypothetical. I flag it as a question, not a finding.

**C6 — Claim 2's central term is undefined and the article supplies no test.** "Overconstrained" is
asserted, never operationalized; "highly important areas" is four words carrying the entire exception.
The five-question test above is *my construction* from official "degrees of freedom" plus this repo's
verb table — it is not the article's, and it should not be attributed to the article. A different
reviewer could draw the line elsewhere and cite the same sentence.

**C7 — Generalization limit.** The article's evidence is Anthropic removing "over 80% of Claude Code's
system prompt… with no measurable loss on our coding evaluations." That is a *system-prompt* result on a
*coding* eval suite, measured against a held-out benchmark. This repo's skills span songwriting,
Kindle DRM management, ADHD workflow shaping, and event storming — domains with no eval suite here and
no measurable-loss signal available. The article's own method (measure, then cut) is not reproducible in
this repository for most of its skills, and claim 5 predicts the non-coding skills are exactly where
particular opinion is densest and least safely trimmed. `evals/` directories exist widely but the docs
note "There is not currently a built-in way to run these evaluations."

## Open questions for the operator

1. **Does this fleet actually overflow the listing budget on target models?** The 1%-of-context budget is
   documented but its char equivalence is not stated on the page, so 104,971 chars cannot be scored from
   docs alone. *Recommendation: measure empirically via `/doctor` on a consumer install before any
   description-trimming work — this is the one finding whose remediation could damage discovery keywords
   if done blind.*
2. **Is a fleet-level always-on budget a criterion this effort should own, or a separate work item?** It
   is the highest-leverage finding but is arguably S11-adjacent rather than S11-proper. *Recommendation:
   own it here as C-4, since no other section's concepts cover the description surface.*
3. **When the article and current official best-practices conflict (C2), which wins for this repo?**
   *Recommendation: official docs win on mechanics (caps, reference depth, examples), the article wins on
   posture (judgment over rules) — and neither overrides `PLUGIN-PHILOSOPHY.md`, which is this
   repository's own deliberate law.*
4. **Should C-3 enforcement extend to the two unenforced official constraints (one-level-deep refs,
   TOC >100 lines)?** *Recommendation: yes — both are mechanically checkable and belong in
   `check-skill.sh` beside the existing caps, routed to the `skill-quality` plugin.*
5. **Do the 7 over-1,024-char descriptions matter (C5)?** *Recommendation: no action; they are compliant
   with the Claude Code cap this marketplace targets. Revisit only if API-surface publication is adopted.*
6. **Does the vendored upstream skill-authoring guidance govern over this section's five-question test?**
   `plugins/playbooks/skills/skill-authoring/vendor/SKILL.md` is upstream authoring guidance sitting
   inside the very population a rightsizing pass would edit — it is excluded from hand-editing as a
   vendor materialization, but its *content* is advice about how to write the other 180 skills. If it
   disagrees with the carve-out defined here, the precedence should be settled before any pass runs.
   *Recommendation: treat it as an input of equal standing to the article — neither overrides
   `PLUGIN-PHILOSOPHY.md`, and any conflict is escalated rather than silently resolved by whoever edits
   first.*

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, any other worktree, or any
other agent's file under `sections/`. My one `docs/topics/` contact was an unavoidable repo-wide grep for
listing-budget awareness, which returned hits from `docs/topics/github-plugin-candidates/PLAN.md` and
`docs/topics/underspecification/PLAN.md`; neither is fenced, and neither is an analysis of this article.
`sections/` was empty when I created it, and I have written only `sections/S11-skills.md`.
