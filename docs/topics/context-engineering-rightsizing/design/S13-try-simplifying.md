# S13 — Try simplifying

Source: `../source-article.md:116-118` (the closing section). One
concept assigned to this section also originates in the article preamble at line 19; it is carried
here as C4 and quoted with its own line number.

## Claims

**C1** — `source-article.md:118`

> Across your system prompt, skills, and CLAUDE.md files, you may need to simplify just like we did.

Simplification applies uniformly across three surfaces: system prompt, skills, CLAUDE.md.

**C2** — `source-article.md:118`

> We rolled out a new command called `claude doctor,`

A new command exists, named `claude doctor`.

**C3** — `source-article.md:118`

> which will help you do this automatically as well.

That command performs the simplification of C1's three surfaces automatically.

**C4** — `source-article.md:19` (preamble; assigned to this section by the brief)

> We've put these best practices in `claude doctor`, use the command /doctor in Claude Code to
> rightsize your skills, and CLAUDE.md files.

`/doctor` rightsizes two things: skills, and CLAUDE.md files.

**C5** — `source-article.md:118`

> For more details on prompting more advanced models specifically, check out our Fable field guide.

A document called "our Fable field guide" exists and contains model-specific prompting detail.

## Evidence status

**C1 — PARTIAL.**

Skills half CONFIRMED, and confirmed more strongly by a non-Claude-Code page than by any Claude Code
page. <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
(fetched this session), "Recommended scaffolding changes":

> **Refactor existing prompts and skills.** Skills developed for prior models are often too
> prescriptive for Claude Fable 5 and can degrade output quality. Review and consider removing older
> instructions if default performance is better.

Same page: *"Capability improvements at this level are also a good prompt to re-evaluate which
instructions, tools, and guardrails are still needed."* That is the article's thesis, stated
officially.

CLAUDE.md half CONFIRMED. <https://code.claude.com/docs/en/commands.md> `/doctor` row:

> Deduplicates local `CLAUDE.md` files against checked-in ones, trims checked-in `CLAUDE.md` files by
> cutting content Claude could derive from the codebase, and migrates the always-loaded guidance that
> remains into skills and nested `CLAUDE.md` files that load on demand. The trim cuts sections such as
> directory layouts, dependency lists, and architecture overviews, and keeps pitfalls, rationale, and
> conventions that differ from tool defaults.

System-prompt half NOT APPLICABLE to this repository's audience, by the article's own concession at
`source-article.md:97`: *"For Claude Code, you will likely never modify this."* The only official
surface for editing a system prompt is the SDK
(<https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts.md>, listed in
<https://code.claude.com/docs/llms.txt>, not fetched — this repo ships no SDK harness). Nothing in
this repo is a system prompt; agent definition bodies are the nearest analogue.

**C2 — CONFIRMED that the command exists; "new" and its capability are both wrong as written.**
<https://code.claude.com/docs/en/cli-reference.md>, verbatim row:

> `claude doctor` — Print read-only installation and settings diagnostics from the terminal without
> starting a session, including install health, settings-file validation errors, and Remote Control
> eligibility. For the in-session setup checkup that can also apply fixes, run `/doctor`

**C3 — UNBACKED.** No official page says `claude doctor` simplifies, rightsizes, or edits anything;
the docs contradict the claim as written. `claude doctor` is read-only; it cannot "do this automatically."
The fix-applying form is the in-session `/doctor` (alias `/checkup`).
<https://code.claude.com/docs/en/debug-your-config.md>:

> From the terminal, `claude doctor` prints read-only installation and settings diagnostics without
> starting a session.

and, for `/doctor`: *"then proposes fixes it applies only after you confirm."* The behavior the
article describes is real, but it is bound to the other command name. Version-gated:
<https://code.claude.com/docs/en/whats-new/2026-w28.md> dates the fix-applying `/doctor` to v2.1.205
and <https://code.claude.com/docs/en/commands.md> gates the CLAUDE.md trim check to v2.1.206+.

**C4 — PARTIAL.** The CLAUDE.md half is confirmed; the skills half is unbacked.

CLAUDE.md: confirmed by the `/doctor` row quoted under C1.

Skills: no page fetched this session says `/doctor` rewrites, shortens, or rightsizes the *content*
of a `SKILL.md`. What it actually does to skills is two utilization/cost measurements:

- <https://code.claude.com/docs/en/commands.md>: *"Finds unused skills, MCP servers, and plugins
  versus their context cost"* — an eviction check, not an edit.
- <https://code.claude.com/docs/en/skills.md> ("Skill descriptions are cut short"): *"Run `/doctor`
  for an estimate of the listing's context cost and its biggest contributors."* — a measurement of
  the always-on skill *listing*, not of skill bodies.

So "rightsize your skills" is true only in the sense of *"delete skills you don't use and shrink the
descriptions of the ones you keep."* Claim UNBACKED for any reading in which `/doctor` edits skill
prose. Pages checked and found silent on it: `commands.md`, `cli-reference.md`, `debug-your-config.md`,
`skills.md`, `whats-new/2026-w28.md`.

**C5 — UNBACKED.** No page named "our Fable field guide" exists; two distinct real artifacts fit the
sentence, neither cleanly, and the article does not link either.

- **Title match, scope mismatch:** <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns>
  — "A field guide to Claude Fable 5: Finding your unknowns", Thariq Shihipar, 2026-07-06. Same author
  as this article, and it is literally called a field guide. But its subject is surfacing unknowns
  before/during/after building — **not** "prompting more advanced models specifically."
- **Scope match, title mismatch:** <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
  — "Prompting Claude Fable 5", subtitled *"Behavioral differences and prompting patterns for Claude
  Fable 5 and Claude Mythos 5, covering effort, instruction following, long runs, memory, and
  scaffolding changes."* Exactly the described content. The phrase "field guide" does **not** appear
  anywhere on the page.

Absence finding, stated with where I looked: no page titled or described as a Fable field guide
appears in <https://code.claude.com/docs/llms.txt> (full index fetched and enumerated this session).
The pointer resolves outside Claude Code's docs in both candidate cases.

## Criteria

**S13-1 ← C1, C3, C4 — Incumbent-first gate on any new simplification artifact (highest leverage).**

- *Surface:* any proposed new artifact in this repo (skill, agent, hook, criteria file, doc) whose
  stated purpose is reducing instruction volume or removing over-constraint.
- *Observable:* the proposal names, by `path:line`, either (a) the `/doctor` capability that already
  covers the surface, or (b) the incumbent repo skill that owns it. If neither can be named, the
  artifact is admissible; if either can, the proposal fails and is downgraded to an edit of the
  incumbent or a pointer.
- *`/doctor`-covered surfaces (fail the gate):* checked-in `CLAUDE.md` content derivable from the
  codebase; local-vs-checked-in `CLAUDE.md` duplication; unused skills / MCP servers / plugins vs
  their context cost; skill-listing context cost and its biggest contributors; slow hooks; invalid
  settings files; duplicate subagent names in one directory.
- *Must NOT flag:* skill **body** length and structure. `/doctor` never inspects a `SKILL.md` body
  (C4), so `plugins/skill-quality/skills/check/SKILL.md:3`'s line caps are not duplication and must
  survive this gate. Agent-definition bodies, hook prompt text, and plugin READMEs are likewise
  uncovered by `/doctor`.

**S13-2 ← C4 — Route "simplify" to the surface that is actually always-on.**

- *Surface:* skill frontmatter `description` + `when_to_use` across `plugins/*/skills/*/SKILL.md`.
- *Observable:* combined `description` + `when_to_use` ≤ 1,536 characters per skill
  (<https://code.claude.com/docs/en/skills.md>: *"the combined `description` and `when_to_use` text is
  truncated at 1,536 characters in the skill listing"*), key use case stated first, and the aggregate
  listing size tracked rather than assumed. Rationale: skill bodies load on demand
  (*"a skill's body loads only when it's used, so long reference material costs almost nothing until
  you need it"*), the listing does not.
- *Must NOT flag:* a long body in a skill whose description is short. Body length is governed by
  S13-3, not by listing cost.

**S13-3 ← C1 — Skill body length uses the official tip, not a locally invented number.**

- *Surface:* `plugins/*/skills/*/SKILL.md` bodies (top-level skills only).
- *Observable:* ≤ 500 lines (<https://code.claude.com/docs/en/skills.md>: *"Keep `SKILL.md` under 500
  lines. Move detailed reference material to separate files."*). Over-length is remediated by
  progressive disclosure into sibling files, never by deleting content.
- *Must NOT flag:* vendored upstream `SKILL.md` copies nested under a skill directory (see Targets).
  Those are synchronized materializations; editing them for length would violate `CLAUDE.md`'s
  never-hand-copy posture and break the sync.

**S13-4 ← C2, C3 — `/doctor` naming precision anywhere this repo cites it.**

- *Surface:* any repo file that mentions the doctor capability (currently: none).
- *Observable:* text that describes applying fixes says `/doctor` (or `/checkup`), never
  `claude doctor`; text that describes read-only terminal diagnostics says `claude doctor`. Any claim
  about the CLAUDE.md trim states the v2.1.206 minimum.
- *Must NOT flag:* prose that names both forms and distinguishes them.

**S13-5 ← C1, C4 — Trim by derivability, not by length.**

- *Surface:* `CLAUDE.md`, `AGENTS.md`, `docs/*.md`, plugin `README.md`.
- *Observable:* content cut must be derivable from the tree (directory layouts, dependency lists,
  architecture overviews); content kept must be non-derivable (pitfalls, rationale, conventions that
  differ from tool defaults). Source: the `/doctor` row at
  <https://code.claude.com/docs/en/commands.md>.
- *Must NOT flag:* a long section that is entirely rationale or gotchas. Length alone is not a
  finding on this surface.

## Targets in this repo

All counts produced by commands run this session in
`<repo-root>`.

**Population — correcting the brief's figure.** The brief says "~181 skills"; that figure is
**correct**, and a naive glob inflates it. `find plugins -path 'plugins/*/skills/*/SKILL.md' | wc -l`
returns **187** because `find`'s `*` crosses `/`. Depth-exact
`find plugins -mindepth 4 -maxdepth 4 -path 'plugins/*/skills/*/SKILL.md' | wc -l` returns **181**
loadable skills across **60** plugins. The 6-file difference is vendored nested copies:

- `plugins/context7/skills/lookup/vendor/cli/SKILL.md`
- `plugins/context7/skills/lookup/vendor/find-docs/SKILL.md`
- `plugins/dometrain/skills/sync/vendor/SKILL.md`
- `plugins/playbooks/skills/boris/vendor/SKILL.md`
- `plugins/playbooks/skills/skill-authoring/vendor/SKILL.md`
- `plugins/playwright/skills/playwright/vendor/SKILL.md`

**Skill bodies (S13-3): zero findings.** Total 25,370 lines across 181 skills (mean ~140).
`find plugins -mindepth 4 -maxdepth 4 -path 'plugins/*/skills/*/SKILL.md' -exec wc -l {} + | awk '$1>500 && $2!="total"'`
returns **nothing**. The repo already fully conforms to the one hard official length figure for
skills. The single `SKILL.md` in the tree over 500 lines is
`plugins/playbooks/skills/boris/vendor/SKILL.md` (1,717 lines) — a vendored copy, tagged
`upstream-version: 8.8.1`, `synced: 2026-06-12` at `plugins/playbooks/skills/boris/SKILL.md:11-12`,
and explicitly out of scope per S13-3.

**Skill listing (S13-2): the real target.** Measured with a Python pass over all 181 frontmatter
blocks: combined `description` + `when_to_use` totals **104,973 characters**, mean 580, longest 1,161
(`plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3`). **Zero** skills exceed the 1,536-char
per-entry cap. But the aggregate is the always-on cost, and
<https://code.claude.com/docs/en/skills.md> states the listing budget *"scales at 1% of the model's
context window"* and that on overflow *"Claude Code drops descriptions starting with the skills you
invoke least"* — silently stripping trigger keywords. 104,973 characters is roughly 26,000 tokens at
4 chars/token. I did not verify whether the 1% fraction is applied to a token count or converted to
characters, so I am not asserting an overflow ratio — but the ambiguity does not have to be resolved
to act: the same page states the `/context` Skills row *"reports the size of the listing after the
budget is applied, so it matches what the model receives"*, which makes the 104,973-character figure
checkable against what actually reaches the model. This is the one surface in this repo where S13's
advice has a measurable, always-paid cost, and `/doctor` already reports it.

**Absence finding — `/doctor` is cited nowhere in this repo.**
`rg -n -e '/doctor|claude doctor|/checkup' --glob '!node_modules' .` returns **zero** matches across
the whole tree. Three shipped skills overlap `/doctor`'s coverage and none of them defers to it or
even mentions it.

**Incumbent skills whose stated purpose already covers S13's advice** (frontmatter descriptions,
`path:line`):

| `path:line` | What it already owns |
|---|---|
| `plugins/claude-config/skills/audit-instructions/SKILL.md:3` | Near-verbatim restatement of the article's thesis: audits CLAUDE.md, rules, **skill bodies**, agent definitions, prompt hooks, output styles for *"instructions current models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions, reasoning-echo directives, stale examples."* Report-only, human-gated. Its own criteria file already cites the official Fable prompting guide at `plugins/claude-config/skills/audit-instructions/reference/criteria.md:38`, and encodes criteria I1–I11 including `I8: Model-era re-audit` and `I10: Reasoning-echo directives`. |
| `plugins/claude-memory/skills/audit/SKILL.md:3` | The memory layer: CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, auto-memory, *"against a codified checklist derived from official Claude Code documentation"*; triggers include *"is my CLAUDE.md too long"*, *"prune instructions"*. |
| `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3` | Exactly `/doctor`'s trim axis, generalized: *"could a fresh agent re-derive its conclusions by exploring the code, config, metadata, and structure itself?"* — verdicts delete / convert-to-pointer / keep-as-derivation-cache / keep-owns-facts. |
| `plugins/docs-hygiene/skills/compress/SKILL.md:3` | The brevity pass: drop flavor, preserve directives, with a semantic-diff revert gate. |
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md:3` | Markdown noise shapes including *"scope/loading meta-commentary"* and hard-coupled enumerated lists. |
| `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:3` | Cross-file duplication → single source of truth, Rule of Three gated. |
| `plugins/re-anchor/skills/tighten-your-output/SKILL.md:3` | Terseness as a live session posture rather than an audit. |
| `plugins/code-tidying/skills/audit-comment-residue/SKILL.md:3` | The comment half of the article's running example — history narration, plan/session references, ticket back-refs. |
| `plugins/skill-quality/skills/check/SKILL.md:3` | Static skill gate: *"listing-budget cap"*, *"line caps"*, *"trigger-keyword preservation vs HEAD"* — i.e. S13-2 and S13-3 are already enforced here. |
| `plugins/playbooks/skills/skill-authoring/SKILL.md:3` | Authoring-time progressive disclosure: *"SKILL.md hub + spoke files"*, description-as-trigger discipline. |
| `plugins/claude-config/skills/audit/SKILL.md:3` | Settings/hooks/plugins/MCP correctness and drift — the surface `/doctor` also checks. |
| `plugins/playbooks/skills/fable-5/SKILL.md:3` | Fable 5 operating doctrine, *"authored by Fable 5 as standing instructions"* — introspected, **not** a copy of the official prompting guide. `plugins/playbooks/skills/fable-5/context/opus-adaptation.md:66` already links the official guide. |

Note the partition these descriptions declare among themselves: `audit-instructions` says outright
*"Not a brevity pass and not memory-layer hygiene"*, ceding brevity to `docs-hygiene:compress` and the
memory layer to `claude-memory:audit`. The repo has already decomposed S13's advice into four
non-overlapping owners plus two enforcement gates. That partition **is** the answer to the
closing-loop question.

## Conflicts and ambiguity

**A. The closing-loop question: S13 warrants zero new artifacts in this repository.** State this
flatly, not as a hedge. The article's closing advice is "simplify"; the measured facts are that this
repo already ships 181 skills totaling 25,370 body lines and 875 markdown files totaling 117,685
lines under `plugins/`, and that four skills plus two gates already own the article's advice with a
declared partition between them. A proportionate response to S13 is: **one pointer**, adding
`/doctor` (and its `claude doctor` sibling) to the three incumbent skills that currently do not
mention it, plus the naming precision in S13-4. A disproportionate response is any new skill, new
criteria file, or new standing rule whose subject is "simplify your instructions" — every such
artifact adds always-on listing cost (S13-2) to solve a problem three existing skills already claim,
and would be self-refuting against the very section it derives from. The gate that decides is S13-1.

**B. `claude doctor` vs `/doctor` — the article names the wrong command.** `source-article.md:118`
attributes automatic simplification to `claude doctor`; the CLI reference says that form is read-only
and redirects to `/doctor` for anything that applies fixes. The preamble at `source-article.md:19`
gets it right, and the two sentences disagree with each other. Anyone acting on the closing sentence
alone runs a command that will not do the thing. This is the sharpest factual conflict in the section.

**C. Official docs contradict themselves on why to shorten a skill, and the resolution changes what
this repo should do.** <https://code.claude.com/docs/en/skills.md> line-level: *"a skill's body loads
only when it's used, so long reference material costs almost nothing until you need it"* versus
*"Once a skill loads, its content stays in context across turns, so every line is a recurring token
cost."* Both are true at different times — deferred at session start, recurring after invocation. For
a 181-skill marketplace whose skills are invoked one or two at a time, the token-cost argument for
shortening bodies is weak and the measured data agrees (zero skills over 500 lines). The argument
that survives is the **over-constraint** one from the official Fable guide — *"too prescriptive… can
degrade output quality"* — which is about instruction content, not length. Any S13-derived work that
frames itself as a byte-reduction exercise is aimed at the wrong failure mode.

**D. `/doctor` does not delete; it relocates — which grows skill count.** The `/doctor` row says it
*"migrates the always-loaded guidance that remains into skills and nested `CLAUDE.md` files that load
on demand."* The article reads as "remove"; the tool's actual behavior is "move to a deferred
surface." For this repo that is a live tension: every migration out of `CLAUDE.md` into a new skill
adds an entry to the always-on listing measured in Targets. The article never acknowledges that
progressive disclosure has a fixed per-skill toll.

**E. The official trim rule is sharper than the article's, and the repo already encodes the sharper
one.** The article's frame is "give Claude judgement, delete rules." The `/doctor` row draws a
different, testable line: cut what is **derivable** (directory layouts, dependency lists,
architecture overviews), keep what is not (pitfalls, rationale, conventions differing from tool
defaults). That axis is exactly
`plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3`. Where the article and the docs differ,
S13-5 follows the docs.

**F. This repo publishes to consumers on unknown models — the article assumes you control the
model.** Every recommendation in the article is conditioned on running Claude 5-class models
("newer models have better judgement"). This repository is a plugin marketplace whose `CLAUDE.md:39-43`
requires plugins to be repo-agnostic and configurable by consumers. Those lines mandate repo- and
config-agnosticism; extending that posture to **model**-agnosticism is my inference, not text this
repo states. A skill de-constrained for Fable 5
judgement can degrade for a consumer on an older model, and the article offers no guidance for
authors shipping to a mixed-model fleet. Stripping guardrails from shipped plugin skills is therefore
a materially riskier act here than it is in Anthropic's own first-party system prompt, which ships
paired to a known model. This is the strongest argument for *not* running a de-constraining sweep
across `plugins/**` on S13's authority alone.

**G. The Fable-guide pointer cannot be resolved from the text.** Detailed under C5. Additionally,
`CLAUDE.md`'s never-hand-copy posture (and the user-global rule on upstream materialization) blocks
any proposal to vendor either candidate guide into this repo; the correct form is the pointer that
`plugins/playbooks/skills/fable-5/context/opus-adaptation.md:66` and
`plugins/claude-config/skills/audit-instructions/reference/criteria.md:38` already use. Note also that
`plugins/playbooks/skills/fable-5/SKILL.md:3` is introspected doctrine authored by the model, not a
restatement of either guide — it is not a duplicate and should not be treated as one.

**I. S13's authority rests on a claim no reader can verify.** "just like we did" inherits
`source-article.md:17` — *"We removed over 80% of Claude Code's system prompt for models like Claude
Opus 5 and Claude Fable 5 with no measurable loss on our coding evaluations."* That is a first-party
result on a first-party system prompt against private evals; it is unfalsifiable from outside
Anthropic and does not transfer to a marketplace's plugin skills. Flagging here for completeness; the
claim itself is presumably S1's to adjudicate.

**H. Version gating makes S13's advice conditional on a version this repo never checks.** The
CLAUDE.md trim requires v2.1.206+; the fix-applying `/doctor` requires v2.1.205+. `rg` finds no
version assertion tied to doctor anywhere in the tree because doctor is never mentioned. Any pointer
added under S13-4 has to carry the floor or it will mislead consumers on older installs.

## Open questions for the operator

1. Does S13 produce **any** repo change, or none at all? *Recommendation: exactly one change — add a
   `/doctor` pointer (with the `claude doctor` distinction and the v2.1.206 floor) to
   `plugins/claude-config/skills/audit-instructions`, `plugins/claude-memory/skills/audit`, and
   `plugins/claude-config/skills/audit`, which currently cite it zero times. No new skill.*
2. Should the ~105,000-character aggregate skill listing be treated as a finding of this effort or
   routed out as separate work? *Recommendation: route it out. It is the highest-value measurement in
   this section but it is a marketplace-scale capacity question, not a digestion of S13; file it
   against `plugins/skill-quality/skills/check`, which already claims the listing-budget cap.*
3. Which artifact does "our Fable field guide" name? *Recommendation: cite the official
   `platform.claude.com/.../prompting-claude-fable-5` — it matches the described content and the repo
   already cites it in three places — and do not cite the blog post, whose subject is unknowns, not
   prompting.*
4. Do we ratify S13-1 (incumbent-first gate) as binding on the other twelve sections' proposals?
   *Recommendation: yes. Without it, twelve independent digests of one article will each propose an
   artifact and collectively contradict the article's closing advice.*
5. Should any de-constraining sweep run across `plugins/**` at all, given Conflict F? *Recommendation:
   no blanket sweep. Restrict de-constraining to skills where the operator controls the consumer, and
   run it through the existing report-only, human-gated `claude-config:audit-instructions` rather than
   as a bulk edit.*

## Fence events

None. No file under `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, or any sibling worktree
was read, listed, or grepped. Repo-wide `rg` invocations were scoped to
`<repo-root>` and returned no hits inside fenced paths. No
other agent's file under `sections/` was read; `sections/` did not exist before this file was written.
