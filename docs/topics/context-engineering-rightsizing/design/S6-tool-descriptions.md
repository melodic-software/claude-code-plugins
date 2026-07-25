# S6 — Then: Repeat yourself / Now: Simple tool descriptions

Source span: `source-article.md:69-74`.

## Claims

**C1.** Section heading — tool descriptions should now be *simple*.

> "**Then: Repeat yourself
> Now: Simple tool descriptions**"

**C2.** Earlier models needed instructions repeated.

> "Earlier Claude models could sometimes need repeated instructions"

**C3.** Positional attention — earlier models weighted late-context instructions over early ones.

> "[Earlier Claude models could] be more likely to listen to instructions at the end of their context
> window than at the start."

**C4.** C2+C3 caused a specific duplication shape in Claude Code's own context.

> "This meant our system prompt would sometimes have references to tools in the main system prompt as
> well as instructions in the tool description."

**C5.** The repeats are deletable without loss on current models.

> "We found we could delete these repeat examples"

**C6.** Placement rule — a tool's usage instructions belong in the tool description, not the system
prompt.

> "and put instructions on how to use tools in the tool descriptions rather than the system prompt."

## Evidence status

| # | Status | Basis |
|---|---|---|
| C1 | **UNBACKED** | No fetched official page states a simplicity norm for tool descriptions. Not addressed at <https://code.claude.com/docs/en/plugins-reference>. |
| C2 | **UNBACKED** | No official page makes any model-generation claim about instruction repetition. The nearest official statements point the *other* way and are about concision, not repetition: "The more specific and concise your instructions, the more consistently Claude follows them" and "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence" (<https://code.claude.com/docs/en/memory>). |
| C3 | **UNBACKED** | No official page asserts that late-context instructions land harder than early ones. The only positional statements in the docs are about *load order*, with no efficacy claim attached: "content is ordered from the filesystem root down to your working directory... so instructions closer to where you launched Claude are read last", and "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself" (<https://code.claude.com/docs/en/memory>). Stating this plainly: the article's causal premise for the whole section has no official backing, and the docs do not deny it either. |
| C4 | **UNBACKED / unverifiable** | Claude Code's system prompt is not published. This is a first-party report about an internal artifact; no fetched page confirms or contradicts it. |
| C5 | **PARTIAL** | No page confirms the specific deletion. A shipped feature embodies the same principle: "The [`/doctor`](https://code.claude.com/docs/en/commands) checkup proposes trims for a checked-in CLAUDE.md: it cuts content Claude can derive from the codebase... and keeps pitfalls, rationale, and conventions that differ from tool defaults" (<https://code.claude.com/docs/en/memory>, min-version 2.1.206). That confirms *a* delete-the-redundant posture, not C5's magnitude. |
| C6 | **PARTIAL — confirmed for the analogue, unbacked for the literal case** | Nothing official about tool descriptions specifically. The identically-shaped rule for skills **is** official: "If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a [skill](https://code.claude.com/docs/en/skills) or a [path-scoped rule](https://code.claude.com/docs/en/memory#path-specific-rules) instead" (<https://code.claude.com/docs/en/memory>). So the placement principle is doc-backed on the surface this repo actually ships. |

## The load-behavior map (what the criteria stand on)

C4/C6 have a precondition the article never states but that its whole logic depends on: **the system
prompt and the tool description are in the same context window on every request.** That is what makes
one of them pure redundancy. Any criterion generalizing S6 must therefore test co-loading first, not
similarity.

Load behavior of every surface this repo ships, each from a fetched page:

| Surface | Enters a Claude Code context window | Citation |
|---|---|---|
| repo `CLAUDE.md` | Every session, in full, as a user message after the system prompt | memory: "loaded into the context window at the start of every session"; "delivered as a user message after the system prompt" |
| skill frontmatter `description` (default) | Every session | skills: "(default) … Description always in context, full skill loads when invoked" |
| skill `description` with `disable-model-invocation: true` | **Never**, until you invoke it | skills: "Description not in context, full skill loads when you invoke" |
| `SKILL.md` body | On invocation only | skills: "a skill's body loads only when it's used" |
| skill supporting files | On demand | skills: "letting Claude access detailed reference material only when needed" |
| agent frontmatter `description` | In the **parent's** context, to decide delegation | sub-agents: "Claude uses each subagent's description to decide when to delegate tasks" |
| agent markdown body | **Only** as the subagent's own system prompt | sub-agents: "The body becomes the system prompt… Subagents receive only this system prompt plus basic environment details… not the full Claude Code system prompt" |
| `AGENTS.md` | **Never** in Claude Code | memory: "Claude Code reads `CLAUDE.md`, not `AGENTS.md`." Verified: this repo's `CLAUDE.md` contains no `@AGENTS.md` import. |
| plugin `README.md` | **No fetched page states it loads.** Treat as human/browse-only | absence finding; searched plugins, plugins-reference, skills |
| `plugin.json` `description` | **No fetched page states it enters context.** Documented as a manifest field ("Brief explanation of plugin purpose"); `displayName` is what is "shown in the `/plugin` picker and other UI surfaces" | plugins-reference |
| MCP tool descriptions | Server-provided. This repo authors **none** | `plugins/dometrain/.mcp.json`, `plugins/miro/.mcp.json` — both point at third-party servers |

**Consequence, stated plainly:** the article's literal surface — a tool description — has effectively
zero footprint here. The only repo-authored surfaces that co-load unconditionally in one window are
**skill `description` ↔ skill `description`** (the listing) and **`CLAUDE.md` ↔ the skill listing**.
One further pair co-loads conditionally but unavoidably: a skill's own `description` never leaves
context, so once the skill is invoked its description and its body are both resident.

## Criteria

### C-S6.0 — Co-loading gate (meta-criterion; all others are subordinate to it)

- **Surface:** any pair of surfaces.
- **Observable:** before a restatement is called an S6 violation, both surfaces must be shown, from a
  fetched doc page, to enter the *same* context window on the *same* request.
- **Fail:** flagged as S6 without that showing.
- **Must NOT flag:** two surfaces that never co-load — a plugin `README.md` and its skills; `AGENTS.md`
  and `CLAUDE.md`; an agent's `description` (parent window) and its body (subagent window). These may
  still be duplication-drift problems, but they are a different anti-pattern with a different
  remediation, and calling them S6 makes the criterion unfalsifiable.

### C-S6.1 — Cross-skill gloss restatement in the always-loaded listing *(highest leverage)*

- **Surface:** skill frontmatter `description` (`plugins/*/skills/*/SKILL.md`).
- **Rule:** a description MAY name a sibling skill for routing. It MUST NOT restate what that sibling
  *does*. Every enabled skill's description is in the same listing, in the same window, on every
  request — so a gloss on a foreign skill is the same fact stated twice in one window, with an
  authoritative definition site (the sibling's own `description`) already present.
- **Observable (fail):** a `/plugin:skill` token naming a skill other than the file's own, carrying an
  appositive gloss, **where the gloss describes the referenced skill rather than a boundary of the
  referring skill**. That direction test is the decidable observable — apply it, not string matching.
  Explanatory framing only: such a gloss is a semantic restatement of the sibling's own
  `description`. Do **not** implement this as paraphrase- or similarity-detection: measured verbatim
  description→body overlap in this repo is near-zero (see C-S6.2 targets), and the glosses in question
  are two-word semantic summaries ("backlog CRUD"), not copied strings. A string-similarity
  implementation returns zero hits and will be mistaken for an empty criterion.
- **Must NOT flag (1):** a bare cross-reference with no gloss — e.g.
  `plugins/testing/skills/plan/SKILL.md:3` naming `/testing:write` and `/toolchain:check` without
  restating them. 73 of the 104 cross-reference occurrences are this shape.
- **Must NOT flag (2):** a negative boundary describing the *referring* skill's own non-trigger, e.g.
  `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3` — "not line-level noise inside a doc
  worth keeping (use /docs-hygiene:audit-noise)". The clause "line-level noise inside a doc worth
  keeping" is a fact about when *audit-derivability* does not fire. Its definition site is this file;
  it is not stated anywhere else. Correctly placed, not a repeat.
- **Discriminator between the two:** does the gloss describe the referenced skill (fail) or the
  referring skill's boundary (pass)?

### C-S6.2 — Procedure resident in the routing surface

- **Surface:** skill frontmatter `description`.
- **Rule:** the description carries routing — what it is, when it fires, when it does not. Operating
  detail belongs in the body, which is the definition site of the procedure and loads only when the
  procedure runs.
- **Observable (fail):** an imperative operational directive in `description` that governs execution
  order, output format, or in-flight behavior, and is not a trigger or boundary statement.
- **Must NOT flag:** an action/verb enumeration such as
  `plugins/skill-quality/skills/check/SKILL.md:3` — "Actions: `check [<skill-name>]` …;
  `validate-evals [<skill-name>]` …". The caller selects the verb *at invocation time*, so the verb
  list is routing, not procedure. Its definition site is the routing surface.
- **Must NOT flag:** length alone. The repo already gates that (`DESC_CHAR_CAP`, 1536 chars,
  `plugins/skill-quality/scripts/check-skill.sh:219`). S6 is about *kind* and *placement*, not size —
  a 1100-char pure-routing description passes.

### C-S6.3 — `CLAUDE.md` restating a skill's own trigger

- **Surface:** repo `CLAUDE.md`, `./.claude/CLAUDE.md`, and `.claude/rules/*.md` **without** a `paths`
  field (memory: "Rules without a `paths` field are loaded unconditionally").
- **Rule:** these load every session; so does every default skill's `description`. Stating "use skill
  X when Y" in `CLAUDE.md` for a skill whose own description already carries trigger Y is the exact
  S6 shape, with `CLAUDE.md` playing the system prompt and the skill description playing the tool
  description.
- **Observable (fail):** a skill named in an always-loaded memory surface together with a trigger
  clause, where that skill's frontmatter `description` already contains an equivalent trigger.
- **Must NOT flag:** a mention of a skill whose frontmatter sets `disable-model-invocation: true`. Per
  the skills doc, that skill's description is **not** in context, so the `CLAUDE.md` mention is the
  only pointer that exists — necessary, not redundant. This exception is decidable mechanically from
  frontmatter, so it does not weaken the check.
- **Must NOT flag:** a pointer with no restated trigger (`docs/PLUGIN-PHILOSOPHY.md` referenced from
  `CLAUDE.md:54` without recapping its content).

### C-S6.4 — Agent `description` carrying work instructions

- **Surface:** `plugins/*/agents/*.md` frontmatter `description` vs body.
- **Rule:** per the sub-agents doc these land in *different* context windows — description in the
  parent, body as the subagent's entire system prompt. So an operating instruction in the description
  is misplaced in both directions, and the fix depends on which:
  - Present in **both** → delete from the description. It is permanently resident in every parent
    context and does no work there.
  - Present in the description **only** → **move it to the body**. It is currently never delivered to
    the agent expected to follow it. This is a correctness defect, not bloat.
- **Must NOT flag:** a dispatch boundary aimed at the parent, e.g.
  `plugins/plugin-quality/agents/auditor.md:3` — "Dispatched by /plugin-quality:audit with an
  evidence-packet path; not intended for direct ad-hoc use." The parent is the party that decides
  dispatch; that is its definition site.
- Note this is **not** an S6 finding under C-S6.0 (the two surfaces do not co-load). It is a placement
  finding derived from C6, and the report must label it as such.

## Targets in this repo

Population by command, run in `<repo-root>`.

**Skills** — `find plugins -name SKILL.md | wc -l` → **187**; of those, `plugins/*/skills/*/SKILL.md`
→ **181** first-class skills. The other 6 are vendored upstream copies under `.../vendor/`
(`plugins/context7/skills/lookup/vendor/cli/SKILL.md`, `.../find-docs/SKILL.md`,
`plugins/dometrain/skills/sync/vendor/SKILL.md`, `plugins/playbooks/skills/boris/vendor/SKILL.md`,
`plugins/playbooks/skills/skill-authoring/vendor/SKILL.md`,
`plugins/playwright/skills/playwright/vendor/SKILL.md`) and are out of scope — they are upstream-owned.

**C-S6.1 (headline).** Descriptions naming another skill: **48 / 181**, **92** unique
(skill, referenced-slug) pairs, **104** token occurrences (a skill may name the same sibling twice).

Of those 104 occurrences, **≥31 carry a gloss**. Precision disclosure, because the operator will
re-run this: the 31 comes from an **adjacency heuristic** — a foreign `/plugin:skill` token followed
by a parenthetical or em-dash gloss within 80 characters. It undercounts. A gloss separated by a
comma or colon, or longer than the window, is missed. **So 31 is a floor on the violation population,
and the residual 73 is "no gloss found adjacent", not a verified pass set.** I hand-read all 8
`work-items` descriptions in full (the densest cluster): every gloss there is the parenthetical shape
the heuristic already catches, so the heuristic is exact for that cluster. The other 41 files carrying
cross-references were not hand-read, so the repo-wide count lies between 31 and 104.

Densest cluster is `work-items`, where **7 of its 8 skills** gloss 4–5 siblings each (`setup` is the
one clean file — it carries no cross-reference at all):

- `plugins/work-items/skills/track/SKILL.md:3` — glosses `/work-items:work`, `:triage`, `:decompose`,
  `:scan-todos`, and `/bug-report:write`
- `plugins/work-items/skills/triage/SKILL.md:3` — "(backlog CRUD)", "(auto-select + execute)",
  "(plan → tickets)", "(TODO sweep)"
- `plugins/work-items/skills/decompose/SKILL.md:3` — same four glosses again
- `plugins/work-items/skills/scan-todos/SKILL.md:3` — same four glosses again
- `plugins/work-items/skills/work/SKILL.md:3`, `:work-loop/SKILL.md:3`, `:attend-queue/SKILL.md:3`

The gloss "(backlog CRUD)" appears in at least four sibling descriptions, while `track`'s own
description already says "the backlog-CRUD multi-verb skill". That fact has one definition site and
five copies, all in the same window, every session.

**Sharpest single instance:** `plugins/work-items/skills/work/SKILL.md:3` glosses its sibling as
"`/work-items:track` (backlog CRUD — add, start, done, list, stats, search, due, recheck, audit)" —
reproducing `track`'s entire verb list, which `track`'s own description already carries verbatim as
"Actions: stats, list, add, start, done, due, recheck, search, audit". Nine verbs, two copies, one
window, every session.

**Clean illustration of the direction test**, in a single clause —
`plugins/work-items/skills/attend-queue/SKILL.md:3`: "Composes /work-items:triage (attention view +
machinery) and /planning:interview." The first reference is glossed with a description of *triage*
(fail); the second is a bare name (pass). Same sentence, same author, opposite verdicts.

Secondary clusters:
`plugins/session-flow/skills/reconcile/SKILL.md:3` (3 glossed refs),
`plugins/source-control/skills/babysit-loop/SKILL.md:3` (2).

**C-S6.2.** Verbatim description→body overlap, measured as the fraction of the description's 6-grams
that also appear in its own body: **1 skill ≥30%** (`plugins/work-items/skills/triage/SKILL.md`,
39.7%), **2 ≥15%** (adds `plugins/work-items/skills/scan-todos/SKILL.md`, 25.8%), **22 ≥5%**, of 181.
Description lengths: max 1161, median 554, min 235 chars; **0 of 181 exceed** the repo's own 1536-char
cap. Literal restatement is therefore **near-absent** — the repo is already clean here, and the
residual signal is again concentrated in `work-items`.

**C-S6.3.** `CLAUDE.md` is **63 lines**. `grep -n "skill\|/[a-z-]*:[a-z-]*" CLAUDE.md` returns exactly
one hit — `CLAUDE.md:20`, a row in the fresh-docs URL table pointing at the official skills page. It
restates no skill trigger and names no in-repo skill. `AGENTS.md` (28 lines) is not loaded by Claude
Code and contains no skill restatement either. **Zero violations. Stated as an absence finding: I
looked in `CLAUDE.md`, `AGENTS.md`, and `.claude/` (which holds only `settings.json` and
`source-control.md`); `ls -d .claude/rules` confirms the repo ships no `.claude/rules/` directory, so
the unconditionally-loaded-rules branch of C-S6.3 has an empty population here.**

**C-S6.4.** Population **7** — all read in full:
`plugins/plugin-quality/agents/auditor.md`, `plugins/review/agents/{architecture-guardian,
ci-log-auditor, code-reviewer, doc-drift-detector, ecosystem-specialist, security-reviewer}.md`.
Descriptions run 242–430 chars against bodies of 47–103 lines, and every one is pure routing
("Use when…", "Use for…", "Dispatched by…"). **Zero violations.**

**Out of scope by C-S6.0, recorded so the next reader does not re-litigate them:**

- `plugins/*/README.md` (**60** files; `plugins/re-anchor/README.md` is 368 lines and tabulates every
  one of its skills' summaries). Never loaded → not S6. Route to duplication-drift.
- `plugin.json` `description` (**60** files; median 348, max 2979 chars —
  `plugins/re-anchor/.claude-plugin/plugin.json`, with `session-flow` at 2472 enumerating "twelve
  skills" and glossing each). These *look* exactly like C-S6.1 violations, but no fetched page states
  this field enters the context window. See Open questions.
- Context-injecting hooks: `grep -rl "SessionStart\|UserPromptSubmit" plugins/*/hooks/hooks.json`
  → **1** (`plugins/session-flow/hooks/hooks.json`), and its `SessionStart` command
  (`hooks/observer-arm.sh`) emits no `additionalContext`. No always-loaded hook text exists to check.

## Cross-plugin byte-identical copies: sanctioned, and unreachable by these criteria

Verdict: **sanctioned exception — and it falls out of C-S6.0 rather than needing a carve-out.**

The three registered clusters (`scripts/cross-plugin-source-registry.txt`) and their populations:

| Cluster | Plugins carrying it | What it is |
|---|---|---|
| `hooks/hook-utils.sh` | 13 | Shell library, `source`d at hook runtime — e.g. `plugins/guardrails/hooks/block-no-verify.sh:38` |
| `reference/artifact-protocol.md` | 4 | Read on demand by an invoked skill via `${CLAUDE_PLUGIN_ROOT}` |
| `reference/standards-contract.md` | 2 | Same; pointed at from `plugins/planning/skills/plan/SKILL.md:82` |

Why no criterion above can flag them:

1. **`hook-utils.sh` never enters a context window at all.** It is executed, not read as instruction.
   C-S6.0 excludes it on the first test.
2. **The `reference/*.md` copies are one statement with N delivery paths, not N statements.** They are
   read on demand, one plugin's copy at a time, by whichever plugin's skill is running. Two copies are
   never both resident as instructions for the same task. S6 requires two *distinct, redundant*
   statements co-loading; this is the opposite — the copies are byte-identical precisely so that no
   second statement exists.
3. **The duplication is forced by a rule this repo states and the official docs back.** `CLAUDE.md:44`
   requires plugins to "reference only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`… No `../`
   reach-outs", because installed plugins run from an isolated cache. Per-plugin materialization is
   the only way to be self-contained; the alternative is a cross-plugin path reference that breaks in
   plugin form.
4. **These files are already the S6 *remedy*, not the disease.**
   `plugins/planning/skills/plan/SKILL.md:82` points at the binding and says the resolution ladder
   "lives there and is not restated in this skill" — the instruction sits at its definition and the
   consumer points rather than repeats. That is precisely C6.

Because C-S6.0 gates every other criterion on demonstrated co-loading, and none of the three clusters
can pass that gate, **no criterion in this section can produce a finding against a registered cluster,
and therefore none can break `scripts/check-cross-plugin-source-drift.sh`.** A criterion phrased on
byte-similarity instead of co-loading *would* break CI — that is the version to reject.

## Conflicts and ambiguity

**1. The section heading contradicts its own body.** C1 says "Simple tool descriptions"; C6 says move
the system prompt's usage instructions *into* the tool description. Descriptions get simpler in one
sense (no longer echoed elsewhere) and richer in another (they absorb the how-to). The article never
reconciles this. A criterion built on "descriptions should be short" would be reading the heading and
ignoring the body. C-S6.2 deliberately tests *kind*, not length, and explicitly does not stack on the
repo's existing 1536-char cap.

**2. The brief's generalization is broader than the claim, and most candidate pairs fail its
precondition.** The tasking framed the payload as "an instruction about X belongs where X is defined,
not restated in a surface that loads alongside it." The clause "that loads alongside it" is
load-bearing and, when applied honestly, disqualifies most of the pairs the brief asked me to map:

| Pair the brief proposed | Co-loads? | Actual classification |
|---|---|---|
| skill `description` vs `SKILL.md` body | Only once invoked | Mostly S4 (progressive disclosure); S6 only for the invoked-case overlap |
| plugin README vs its skills | No — README never loads | Duplication-drift, not S6 |
| repo `CLAUDE.md` vs the owning skill | Yes, for the always-loaded portion | **Genuine S6** (C-S6.3) — and this repo is already clean |
| agent definition vs the skill it invokes | No — different windows | Placement finding (C-S6.4), not S6 |
| skill `description` vs another skill's `description` | **Yes, always** | **Genuine S6** (C-S6.1) — 31 instances |

So S6's footprint here is **much smaller than the section's prominence suggests**: 31 glossed
cross-references, concentrated in one plugin. Reporting the 368-line `re-anchor/README.md` or the
2979-char `plugin.json` descriptions as S6 hits would be a category error — they are never in context.

**3. C3 is the section's causal premise and it is UNBACKED, which weakens C5 more than C6.** The
argument runs: models used to over-weight late context → therefore we repeated ourselves → therefore
the repeats are now deletable. If C3 has no backing, C5's "we can delete these" rests on the article's
own unpublished evals, not on a mechanism anyone can check. C6, by contrast, survives independently:
even if positional attention were still real, an instruction resident in every window for a tool used
in few of them is a token cost regardless. **Criteria should be derived from C6, not C3.** The
repo-level implication is that a rightsizing pass justified by "the model no longer needs repetition"
is unfalsifiable, whereas one justified by "this fact has one definition site and five copies in one
window" is measurable — and C-S6.1 is written the second way.

**4. Negative routing is not a repeat, and a naive criterion would delete it.** "Not for X — use
`/a:b`" states a boundary of the *referring* skill. Its only definition site is that skill's own
description; the sibling's description does not carry it (a skill does not enumerate what other skills
should not be used for). Every C-S6.1 must-not-flag case exists to protect this. This repo uses the
pattern heavily and deliberately — `plugins/work-items/skills/triage/SKILL.md:3`,
`plugins/naming/skills/name-it-better/SKILL.md:3`, `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:3`.
The violation is the *gloss on the sibling*, never the disambiguation itself.

**5. C6 does not transfer cleanly to skills, because skills have a lazy body and tools do not.** A
tool description is the only surface a tool has, so it must carry both "when" and "how". A skill has
two surfaces with different load behavior, so the article's single rule splits into two: **when →
description, how → body**. The article gives no guidance on this split because it never had to. This
is an extrapolation, and C-S6.2 is labeled as the weaker criterion because of it.

**6. `AGENTS.md` is a near-miss worth recording.** `AGENTS.md:26` and `CLAUDE.md:61` both state
the Conventional Commits PR-title rule. Under a similarity-based criterion this is a textbook S6 hit.
Under C-S6.0 it is not one at all: "Claude Code reads `CLAUDE.md`, not `AGENTS.md`", and this repo's
`CLAUDE.md` does not import it. The overlap is a real cross-vendor drift risk — the two files can
diverge and no gate notices — but the remediation is the doc's `@AGENTS.md` import, not deletion. This
is the clearest illustration of why the co-loading gate is the whole criterion.

## Open questions for the operator

1. Does `plugin.json` `description` enter the context window? No fetched page says so; it is documented
   as a manifest field and `displayName` is what the `/plugin` picker shows. **Recommendation:** treat
   as browse-only and route the 60 descriptions (median 348, max 2979 chars, several enumerating and
   glossing every skill in the plugin) to duplication-drift, not S6 — and settle it empirically with
   `/context` in a session with the marketplace installed before any rightsizing pass touches them.
2. Should C-S6.1 remediation delete the glosses or hoist them to one owner? **Recommendation:** delete
   the glosses and keep the bare names. The sibling's own description is already in the same window,
   so the name alone resolves; a plugin-level "here is the family" surface would just relocate the
   repeat.
3. Should C-S6.2 ship at all, given it is an extrapolation past the article (conflict 5) and the
   measured population is 1–2 skills? **Recommendation:** ship it as advisory-only, not a CI gate. The
   repo's existing 1536-char cap already catches the pathological case.
4. C-S6.4 finds zero violations across all 7 agents. Should it become a gate anyway? **Recommendation:**
   yes — it is cheap, the population is fixed and small, and its description-only branch catches a
   correctness bug (an instruction never delivered to the subagent), not merely bloat.
5. Should the `work-items` gloss cluster be fixed as part of this effort or filed separately? It is 7
   files and the single densest S6 signal in the repo. **Recommendation:** file separately —
   digestion output should not become an edit, and the brief forbids edits outside `sections/`.

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, or any other worktree.

One disclosure for completeness: during first orientation, before any agent could have written
anything, I ran `ls sections/` at the repository root. It returned "no sections dir" — the path did
not exist. No other agent's output was listed or seen. I then created
`.work/context-engineering-rightsizing/sections/` with `mkdir -p` to write this file, and never
listed or read that directory afterward. All repository reads were confined to
`<repo-root>`. Every official-doc citation was fetched this
session via WebFetch from `code.claude.com`.
