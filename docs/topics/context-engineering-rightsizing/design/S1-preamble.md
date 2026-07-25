# S1 — untitled preamble

Scope: `source-article.md:11` through `source-article.md:19` (everything before `## Unhobbling Claude`).

All official-documentation facts below were fetched this session (2026-07-24) via WebFetch. Local
environment fact: `claude --version` → `2.1.219 (Claude Code)`.

## Claims

1. **Prior-work reference.** "I've written previously about how to best prompt the newest generation
   of Claude 5 models and work with them iteratively to discover what you want to build."
2. **Prompt is a minority of context.** "But when you send a message to Claude, the prompt is only a
   small part of the context it gets."
3. **Named context sources.** "Much of your context is assembled from your system prompt, Skills,
   CLAUDE.md files, memory, and other sources."
4. **Term definition and impact.** "We call this context engineering, and it makes a big impact on
   the results you generate when using Claude Code or in building your own agents."
5. **Generality forces imprecision.** "Unlike a prompt, context is used generally across many
   requests, so it cannot be as specific."
6. **Authoring under prompt-uncertainty.** "How do you build these general prompts and guidance for
   Claude, especially when you don't know what a user's prompt might be?"
7. **Difficulty tracks capability drift.** "This can be surprisingly difficult as Claude's own
   capabilities evolve."
8. **A discontinuity was observed.** "Most recently, we noticed a large jump in the way we prompt the
   newest generation of Claude models."
9. **The 80% removal.** "We removed over 80% of Claude Code's system prompt for models like Claude
   Opus 5 and Claude Fable 5 with no measurable loss on our coding evaluations."
10. **Practices are embedded in the tool.** "We've put these best practices in `claude doctor`, use
    the command /doctor in Claude Code to rightsize your skills, and CLAUDE.md files."

## Evidence status

**1 — PARTIAL.** The referenced prior work exists as first-party prompting guides
(`https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5`,
`.../prompting-claude-fable-5`, surfaced by WebSearch restricted to `anthropic.com`/`claude.com`).
I did **not** fetch those page bodies, so "what they say" is unverified; only their existence is
established. The article's closing line points at "our Fable field guide," presumably the same set.

**2 — CONFIRMED.** `https://code.claude.com/docs/en/context-window.md` states in its narrated
walkthrough: *"Your prompt is tiny compared to what's already loaded. Most of Claude's context is
project knowledge, not your words."* The same page's illustrative model puts the system prompt at
4,200 tokens before the user types anything, alongside auto memory, environment info, MCP tool names,
skill descriptions, user `CLAUDE.md`, and project `CLAUDE.md`.

**3 — PARTIAL (incomplete enumeration).** Every named source is real and documented, but the official
enumeration is strictly larger. `context-window.md:1579` (fetched): *"Before you type anything:
CLAUDE.md, auto memory, MCP tool names, and skill descriptions all load into context. Your own setup
may add more here, like an [output style] or text from [`--append-system-prompt`], which both go into
the system prompt the same way."* `https://code.claude.com/docs/en/debug-your-config.md` lists the
`/context` categories as *"system prompt, system tools, MCP tools, custom subagents with the source
each loaded from, memory files, skills, and conversation messages."* Two sources the article's list
does not name are load-bearing here: **`.claude/rules/`** (`memory.md`: *"Rules without `paths`
frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`"*) and **output
styles** (`glossary.md`: *"A configuration that modifies Claude's system prompt"*). The article's
"and other sources" is doing heavy lifting.

**4 — UNBACKED as a Claude Code product term.** I read the full A–W body of
`https://code.claude.com/docs/en/glossary.md`. It defines *context window*, *CLAUDE.md*, *auto
memory*, *skill*, *rules*, *output style*, *bundled skills*, and *agentic harness*. It contains **no
entry for "context engineering"** and no definition of the phrase anywhere on the page. The term is
Anthropic-authored blog/engineering vocabulary, not documented product vocabulary. The "makes a big
impact" half is an unquantified assertion with no cited measurement.

**5 — PARTIAL, and in direct tension with official guidance.** The *"used generally across many
requests"* half is CONFIRMED: `memory.md` says CLAUDE.md files "are loaded into the context window at
the start of every session" and are "loaded in full regardless of length." The *"cannot be as
specific"* half is contradicted in emphasis by `memory.md` § *Write effective instructions*:
*"**Specificity**: write instructions that are concrete enough to verify. For example: 'Use 2-space
indentation' instead of 'Format code properly'… 'API handlers live in `src/api/handlers/`' instead of
'Keep files organized'."* and by `debug-your-config.md`: *"Adherence drops when an instruction is
vague enough to interpret multiple ways."* See Conflicts §1 — the reconciliation is that the article
means *narrowness of applicability*, not *precision of wording*, but the sentence as written invites
the wrong edit.

**6 — UNBACKED (rhetorical framing, not a factual claim).** No official page frames context authoring
as an unknown-prompt problem. Recorded so it is not silently merged into claim 5.

**7 — UNBACKED.** First-party narrative. No official page states that context-engineering practice
becomes harder as model capability changes.

**8 — UNBACKED.** First-party narrative about Anthropic's internal prompting practice. Unfalsifiable
from outside.

**9 — UNBACKED by product documentation; first-party-sourced only.** The claim traces to exactly one
place: this same post, published as
`https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`
(fetched: author **Thariq Shihipar, member of technical staff, Anthropic**; publication date **July
24, 2026** — today). No page under `code.claude.com` states any system-prompt reduction figure. No
eval suite, baseline, model pairing, or measurement window is published. `context-window.md` gives a
4,200-token system prompt as *"illustrative"* only (the page's own tooltip: *"Token counts are
illustrative"*), so it cannot corroborate a before/after ratio. Treat "over 80%" and "no measurable
loss" as unaudited vendor self-report.

**10 — SPLIT: one third CONFIRMED, one third CONTRADICTED, one third UNBACKED.** This is the claim
the brief asked me to verify hard; findings in full below.

### Claim 10 verified against `commands.md`, `debug-your-config.md`, `memory.md`, `skills.md`, `cli-reference.md`, `headless.md`

**(a) CLAUDE.md rightsizing — CONFIRMED, and richer than the article says.**
`https://code.claude.com/docs/en/commands.md`, `/doctor` row, verbatim: *"Run a setup checkup that
diagnoses issues and can fix them. Checks installation health… Finds unused skills, MCP servers, and
plugins versus their context cost, flags slow hooks, and checks for a newer version on your release
channel. **Deduplicates local `CLAUDE.md` files against checked-in ones, trims checked-in `CLAUDE.md`
files by cutting content Claude could derive from the codebase, and migrates the always-loaded
guidance that remains into skills and nested `CLAUDE.md` files that load on demand. The trim cuts
sections such as directory layouts, dependency lists, and architecture overviews, and keeps pitfalls,
rationale, and conventions that differ from tool defaults.** Also offers to make auto mode your
default and to pre-approve frequently denied read-only commands. Reports findings first and asks for
confirmation before changing anything… Alias: `/checkup`."* `memory.md` repeats the trim rule
verbatim in its "My CLAUDE.md is too large" section.

**(b) "rightsize your skills" — PARTIAL as written; UNBACKED under the narrow reading.** The
distinction matters because S1-C3 hangs on it, so both readings are stated:

- *"`/doctor` acts on skills at all"* — **PARTIAL/supported.** `commands.md` documents two
  skill-touching behaviors: it *"Finds unused skills, MCP servers, and plugins versus their context
  cost"* (a keep/drop signal on whole skills), and it *"migrates the always-loaded guidance that
  remains into skills"* (skills as the destination of migrated CLAUDE.md content).
- *"`/doctor` will simplify my `SKILL.md` files"* — **UNBACKED.** No fetched page says `/doctor`
  inspects, trims, splits, or edits the body of an existing `SKILL.md`.

The operative mechanism claim: `/doctor` may propose **dropping** a skill; nothing documents it
proposing to **shrink** one.

**(c) "We've put these best practices in `claude doctor`" — CONTRADICTED for the terminal form.**
`cli-reference.md`, verbatim: *"`claude doctor` | Print read-only installation and settings
diagnostics from the terminal without starting a session, including install health, settings-file
validation errors, and Remote Control eligibility. For the in-session setup checkup that can also
apply fixes, run `/doctor`."* `debug-your-config.md` repeats: *"From the terminal, `claude doctor`
prints read-only installation and settings diagnostics without starting a session."* The rightsizing
lives **only** in the in-session `/doctor`. The article's sentence names the CLI form first and is
wrong about it; its own "use the command /doctor in Claude Code" is the correct instruction.

**(d) Version floor — CONFIRMED, two distinct floors.** `commands.md` and `memory.md` both carry the
marker *"The `CLAUDE.md` trim check requires Claude Code v2.1.206 or later."* Separately: *"Before
v2.1.205, `/doctor` opened a read-only diagnostics screen and pressing `f` sent the report to
Claude,"* and *"Before v2.1.205, `/doctor` was a built-in command rather than a bundled skill"*
(`skills.md`). So: **< 2.1.205** = read-only screen, no rightsizing at all; **2.1.205–2.1.205** =
bundled skill, no CLAUDE.md trim; **≥ 2.1.206** = trim available. Local install is **2.1.219**, so
every documented behavior is available on this machine.

**(e) Can it be absent or disabled — YES, four documented ways.** `skills.md`, verbatim: *"Bundled
skills are available in every session. To turn them off, use the `disableBundledSkills` setting,
which disables every bundled skill except `/doctor`."* and *"The `/doctor` setup checkup stays typable
when `disableBundledSkills` is on, in Claude Code v2.1.205 and later. To hide it, set the
`DISABLE_DOCTOR_COMMAND` environment variable or a `skillOverrides` entry of `"doctor": "off"`."*
Additionally `skills.md` documents *"**Disable all skills** by denying the Skill tool in
`/permissions`"*, and `cli-reference.md` documents `--safe-mode` / `headless.md` documents `--bare`,
both of which skip skill discovery. A version below 2.1.206 is the fifth way it is effectively absent.

**(f) Non-interactive drivability — PARTIAL, and the gate is the confirmation step.** `headless.md`,
verbatim: *"User-invoked skills and custom commands work in `-p` mode: include `/skill-name` in the
prompt string and Claude Code expands it before running. Built-in commands that only run in the
terminal interface, such as `/login`, aren't available in `-p` mode."* `/doctor` is a bundled skill
(`skills.md`), not a terminal-only built-in, so `claude -p "/doctor"` is expandable in principle. But
`commands.md` states `/doctor` *"Reports findings first and asks for confirmation before changing
anything."* **No fetched page states what that confirmation resolves to under `-p`, under
`--permission-mode acceptEdits`, or under `dontAsk`.** I did not run it, so I assert nothing about
the outcome. Treat automated `/doctor` in CI as unverified, not as available.

**(g) Scope boundary the article obscures — `/doctor`'s trim targets *checked-in* CLAUDE.md.** Both
`commands.md` and `memory.md` say "trims **checked-in** `CLAUDE.md` files" and "deduplicates **local**
CLAUDE.md files against checked-in ones." `memory.md`'s scope table defines "Local instructions" as
`./CLAUDE.local.md` and "User instructions" as `~/.claude/CLAUDE.md`. **No fetched page places
`~/.claude/CLAUDE.md` inside the trim's scope.** This matters directly for the second audience in the
brief.

## Criteria

**S1-C1 — Enumerations of "what loads into context" must be open or canonical.**
*Surface:* any SKILL.md body, `reference/`/`context/` spoke file, plugin README, repo `docs/`, or
`CLAUDE.md` that tells a reader where context comes from.
*Observable:* the artifact presents a closed list of context sources (no "see <official page> for the
current list", no explicit narrowing clause) **and** omits any of `.claude/rules/`, output styles,
MCP tool listings, subagent definitions, or plugin-supplied skills.
*Pass/fail:* fail if closed **and** incomplete. Pass if it links `https://code.claude.com/docs/en/context-window`
or `.../memory` as the live source, or if it is explicitly scoped ("the three surfaces this skill
edits").
*Must NOT flag:* an artifact that deliberately lists only the surfaces it operates on — e.g.
`plugins/claude-memory/skills/audit/` enumerating its own audit targets — because that is a scope
declaration, not a claim about what Claude Code loads.

**S1-C2 — Any `/doctor` behavioral claim carries scope, form, and version.**
*Surface:* SKILL.md bodies, spoke files, plugin READMEs, repo `docs/`.
*Observable:* a hit on `/doctor` or `claude doctor` that asserts what it *does* must satisfy all
three: (i) does not attribute SKILL.md-body rewriting to it; (ii) distinguishes in-session `/doctor`
(applies fixes after confirmation) from terminal `claude doctor` (read-only, no session); (iii) names
the v2.1.206 floor when the CLAUDE.md trim is the behavior invoked.
*Must NOT flag:* `plugins/ai-briefing/skills/generate/references/slide-generation.md:247`, which
routes a user to run `/doctor` as a troubleshooting step and makes no behavioral claim about it.

**S1-C3 — `/doctor` can propose dropping this repo's skills; it never proposes shrinking them.**
*Surface:* any plan, spec, or skill produced by this rightsizing effort.
*Observable:* the artifact proposes `/doctor` as the mechanism for reducing or restructuring the
**content** of `plugins/*/skills/*/SKILL.md`.
*Pass/fail:* fail. Documented `/doctor` skill behavior is unused-skill/context-cost detection and
CLAUDE.md→skill migration. Neither is a rewrite of a skill body, so every body-level rightsizing
decision over the 187 skills has to be built here.
*Reach, verified:* this marketplace **is** installed at user scope on this machine — the plugin
directory names enumerated by `ls plugins` (`claude-config`, `docs-hygiene`, `re-anchor`,
`plugin-quality`, `playbooks`, `session-flow`, `work-items`, …) match the `plugin:skill` namespaces in
this session's own skill listing. So `/doctor`'s *"Finds unused skills, MCP servers, and plugins
versus their context cost"* check does reach them, and can recommend disabling a plugin this
repository authors. That is the reachable half; body content is the unreachable half.
*Must NOT flag:* proposing `/doctor` for this repo's own root `CLAUDE.md` (checked in, squarely in
scope), or proposing it as an *unused-skill* signal over the installed marketplace.

**S1-C4 — "Less constrained" must never be authored as "less specific."**
*Surface:* any guidance this effort writes into SKILL.md, CLAUDE.md, or repo docs.
*Observable:* an instruction directing authors to make context vaguer, more general, or less concrete
in wording.
*Pass/fail:* fail, citing `memory.md` § *Write effective instructions* ("write instructions that are
concrete enough to verify") and `debug-your-config.md` ("Adherence drops when an instruction is vague
enough to interpret multiple ways").
*Must NOT flag:* instructions to make content **shorter**, to **defer** it behind progressive
disclosure, or to **delete** a rule outright. Those change scope and volume, not precision.

**S1-C5 — A repo carrying both `AGENTS.md` and `CLAUDE.md` must wire one to the other.**
*Surface:* repository root.
*Observable:* `AGENTS.md` exists, `CLAUDE.md` exists, and `CLAUDE.md` contains no `@AGENTS.md` import
and is not a symlink to it.
*Pass/fail:* fail — `memory.md`: *"Claude Code reads `CLAUDE.md`, not `AGENTS.md`. If your repository
already uses `AGENTS.md` for other coding agents, create a `CLAUDE.md` that imports it."*
*Must NOT flag:* a repo with `AGENTS.md` alone (no CLAUDE.md), where the file is unambiguously for a
different tool, or one where `CLAUDE.md` opens with `@AGENTS.md`.

**S1-C6 — The 80% figure, if cited, is cited as vendor self-report.**
*Surface:* any artifact this effort produces.
*Observable:* the figure appears without naming the blog post + date, or is framed as product
documentation / measured fact.
*Pass/fail:* fail. Correct form names
`https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`
(Thariq Shihipar, 2026-07-24) and states that no eval data is published.
*Must NOT flag:* a citation that carries the source and the caveat, however brief.

## Targets in this repo

Populations measured by command in `<repo-root>`, not
estimated:

| Command | Result |
|---|---|
| `find plugins -name SKILL.md \| wc -l` | **187** (identical to `find plugins -path "plugins/*/skills/*/SKILL.md"`) |
| `find plugins -maxdepth 1 -mindepth 1 -type d \| wc -l` | **60** plugins |
| `find . -name "CLAUDE.md" -not -path "./.git/*"` | **1** — `./CLAUDE.md` only |
| `wc -l CLAUDE.md AGENTS.md` | **63** and **28** lines |
| `find plugins -path "*/agents/*.md"` | **7** agent definitions |
| `grep -rn -i "/doctor\|claude doctor" --include="*.md" .` (excl. `.work/`) | **8 hits across 6 files** |
| `ls -d .claude/rules` | **absent** — no rules directory |
| `grep -rn "80%" --include="*.md" .` (excl. `.work/`) | 10 hits, **none** about system-prompt reduction |

Concrete file hits:

- `CLAUDE.md:1-63` — the only CLAUDE.md, 63 lines, comfortably under the documented 200-line target
  (`memory.md`: *"target under 200 lines per CLAUDE.md file"*). It is **not** an obvious `/doctor`
  trim candidate: its bulk is `CLAUDE.md:13-30`, a fresh-docs URL table, and `CLAUDE.md:37-50`, design
  rules — both are "conventions that differ from tool defaults," explicitly on `/doctor`'s keep list,
  not derivable directory-layout content.
- `AGENTS.md:1-28` **(S1-C5 failure)** — `grep -n "AGENTS" CLAUDE.md` returns nothing and `ls -la`
  shows both as regular files, not symlinks. Under `memory.md`'s stated behavior these 28 lines never
  enter a Claude Code session: the standards-sync warning at `AGENTS.md:9-17`, the `git add -A`
  prohibition at `AGENTS.md:19-23`, and the PR conventions at `AGENTS.md:25-28` are invisible to
  Claude Code today. Two of those three are *gotchas* — exactly the content `/doctor`'s trim rule says
  to keep, sitting in the one file Claude Code does not read.
- `plugins/claude-config/skills/audit/context/validation-categories.md:110` **(S1-C2 candidate)** —
  asserts *"`/doctor` needs an interactive TTY — prompt the user to run it."* Current docs support a
  weaker statement: applying fixes requires confirmation, and `claude doctor` explicitly runs from a
  terminal *without a session*, while `headless.md` states user-invoked skills expand in `-p` mode.
  The line overstates what is documented. It is a drift candidate, not a confirmed error — see Open
  Questions.
- `plugins/claude-config/skills/audit/context/validation-categories.md:66,108` and
  `plugins/claude-config/skills/audit/SKILL.md:119` — three `/doctor` claims about settings-error
  reporting and skill-listing overflow. The settings claim is corroborated (`debug-your-config.md`:
  *"`claude doctor` reports the validation failure"*). The listing-overflow claim maps plausibly onto
  *"Finds unused skills … versus their context cost"* but is not stated in those terms by any fetched
  page — flag as PARTIAL, not as an error.
- `plugins/re-anchor/skills/use-your-skills/SKILL.md:96` and its
  `evals/evals.json:32` — both say `/doctor` "estimates the listing cost." Same PARTIAL status; the
  eval fixture will need the same correction as the skill if the wording is tightened, or the eval
  will encode the drift.
- `docs/topics/ai-adoption-ladder/design/RESEARCH-product-surface.md:97` — already names the
  "`/doctor` trim" alongside `autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, and the
  `InstructionsLoaded` hook. Accurate as written; passes S1-C2 (no skill-rightsizing attribution).
- `plugins/ai-briefing/skills/generate/references/slide-generation.md:247` — explicit S1-C2
  must-not-flag case; verified it makes no behavioral claim.
- **187 SKILL.md files** — reachable by `/doctor` only as unused-skill/context-cost candidates, never
  as content to shrink (S1-C3). Body-level rightsizing has to be built here.

**User-global scope (read-only to this effort; routed as recommendations, never edited):**

- `~/.claude/CLAUDE.md` — **69 lines** (`wc -l`), well under `memory.md`'s
  *"target under 200 lines per CLAUDE.md file."* It is **not** oversized and is **not** reachable by
  `/doctor`'s trim, which is documented against *checked-in* CLAUDE.md (claim 10g). Both facts point
  the same way: no `/doctor`-driven action is available or needed here.
- `~/.claude/docs/` — **5 files** (`ls`), referenced from that CLAUDE.md's
  "Reference docs (read on demand)" section rather than inlined. This is a **positive finding** for
  claims 3 and 10: the user-global surface already implements the pointer-style progressive
  disclosure the official docs endorse (`skills.md`: *"a skill's body loads only when it's used, so
  long reference material costs almost nothing until you need it"*). Any pass here should confirm the
  pattern, not disturb it. Note the routing constraint: this surface is chezmoi-managed, so a change
  goes through the dotfiles repo's own flow, not through a direct edit.

**Absence findings, with where I looked:** no `.claude/rules/` directory (`ls -d .claude/rules`); no
nested/subdirectory `CLAUDE.md` anywhere in the tree (`find . -name "CLAUDE.md" -not -path "./.git/*"`
returns one path); `.claude/settings.json` contains only `{"worktree": {"baseRef": "head"}}` — no
`disableBundledSkills`, no `skillOverrides`, no `claudeMdExcludes`, so nothing in this repo suppresses
`/doctor` or the bundled skills; and no repo file cites the 80% figure.

## Conflicts and ambiguity

**1. "cannot be as specific" (claim 5) vs. official adherence guidance — the sharpest conflict in
this section.** `memory.md` tells authors to be *more* concrete ("Use 2-space indentation" over
"Format code properly"); `debug-your-config.md` says adherence *drops* when instructions are vague.
The article says context "cannot be as specific." Both can be true only under a distinction the
article never draws: context must be **general in applicability** (it fires across unknown prompts)
while remaining **precise in wording** (a vague rule is a worse rule at any scope). A pass that reads
claim 5 literally will produce exactly the failure `debug-your-config.md` warns about. **This
distinction should be written down explicitly wherever the article's framing is adopted.**

**2. The article's own tool sentence is internally inconsistent (claim 10).** "We've put these best
practices in `claude doctor`" and "use the command /doctor in Claude Code" name two different things
that current docs deliberately separate: the CLI form is read-only and sessionless; only the
in-session form applies fixes. Anyone acting on the first half — e.g. scripting `claude doctor` in CI
expecting rightsizing — gets diagnostics and nothing else.

**3. "rightsize your skills" does not survive contact with the docs (claim 10b).** This is the gap
most likely to misdirect the effort: the article promises tool support for skill rightsizing that no
fetched page describes. For a repo whose primary artifact class is 187 authored skills, the
practical translation is *"`/doctor` will not do this for us."*

**4. `/doctor`'s trim does not reach user-global scope (claim 10g) — and that is the second audience
in the brief.** The trim is documented against *checked-in* CLAUDE.md; `~/.claude/CLAUDE.md` is
"User instructions" in `memory.md`'s own scope table and is nowhere named as a trim target. The
surface is also chezmoi-managed and read-only to this effort. So it is reachable by neither the tool
the article recommends nor by this repo's edit permissions — every user-global finding routes as a
recommendation through the dotfiles repo. In this case the measured state is healthy (69 lines,
reference docs already externalized), so the gap is latent rather than active: it matters the moment
that file grows, and no automated check will catch it when it does.

**5. The repo already carries a stronger position than the article's (claim 4).**
`plugins/playbooks/skills/boris/reference/orchestration.md:49` records: *"The progression: Sonnet 3.5
= prompt engineering; Opus 4 = context engineering; today's models need neither. Boris: minimal system
prompt, minimal tools, give the model a way to fetch context, get out of the way."* The article
elevates context engineering as the discipline that "makes a big impact"; the repo's vendored Boris
material calls it a superseded era and names *context minimalism* as the successor
(`plugins/playbooks/skills/boris/vendor/SKILL.md:174,1499`). These are not reconcilable by wording —
they are different theses about whether the practice still matters. Both are first-party Anthropic
voices. Note that the practical prescriptions converge (both say: cut, defer, let the model fetch);
only the framing conflicts. **Do not let the article's vocabulary silently overwrite the repo's
existing position without the operator deciding.**

**6. Claim 3's list, adopted verbatim, would teach an incomplete model.** Omitting `.claude/rules/` is
the material gap: rules load at launch with the same priority as `.claude/CLAUDE.md` and are the
documented *destination* for content trimmed out of an oversized CLAUDE.md. A rightsizing pass that
only knows about "CLAUDE.md, skills, memory" has one fewer place to move things to.

**7. Claim 9 generalizes from a case that does not transfer.** Anthropic removed 80% of a system
prompt it *owns*, measured against evals it *owns*, for models it *ships*. A plugin marketplace has
none of those three: no evals over its 187 skills, no control over the consuming repo's context, and
consumers on unknown Claude Code versions and models. "80% is removable" is not a defensible prior
here; the transferable part is the *method* (delete, measure, keep the deletion only if the measure
holds), and this repo currently has no such measure.

**8. Claim 2 is true but load-bearing in a way the article does not flag.** `context-window.md` shows
skill *descriptions* — not bodies — occupying startup context, and adds a detail relevant to a
marketplace: *"Unlike the rest of the startup content, this listing is not re-injected after
`/compact`. Only skills you actually invoked get preserved."* The always-on cost of 187 skills is
carried by descriptions; that is a different optimization target than skill body length, and the
preamble's framing does not separate them.

## Open questions for the operator

- **Does `/doctor` apply fixes under `claude -p`, or is `validation-categories.md:110`'s "needs an
  interactive TTY" correct?** Docs establish `-p` expansion and a confirmation gate but not their
  interaction. *Recommendation: run `claude -p "/doctor"` once in a throwaway clone and settle it
  empirically before anyone edits that line — I did not run it, since `/doctor` can write files.*
- **Does the article's framing or the repo's existing "context minimalism" framing win in this
  repo's vocabulary (Conflict 5)?** *Recommendation: keep the repo's Boris-sourced framing as the
  position and treat this article as corroborating evidence for the prescriptions, since the
  prescriptions agree and only the labels differ.*
- **Is `AGENTS.md` supposed to be invisible to Claude Code (S1-C5)?** It may be a deliberate
  Codex/other-agent-only file. *Recommendation: add `@AGENTS.md` as the first line of `CLAUDE.md` —
  the three rules in it are gotchas Claude Code should hold, and `memory.md` documents this exact
  pattern. Confirm the intent first; the fix is one line either way.*
- **Should this effort adopt the official 200-line CLAUDE.md target as a repo criterion, given the
  repo's single CLAUDE.md is already at 63?** *Recommendation: yes, but as a criterion the repo's
  **plugins** apply to consumers' CLAUDE.md files, not as a self-check — it is non-binding here and
  binding downstream.*
- **Does this effort need a measurement before it deletes anything (Conflict 7)?** *Recommendation:
  yes for skill bodies, no for demonstrably dead content. `skills.md` documents the baseline method:
  "run each one in a fresh session with the skill available and again with it disabled, and compare."
  Adopting deletion without any such gate imports the article's confidence without its evals.*

## Fence events

None. I read nothing from any fenced path. My searches were repo-wide `grep`/`find` rooted at my own
working directory, and a re-run filtered for `context-engineering-claude-5|fable-field-guide` returned
**zero hits**, so no fenced material appeared in any result set I inspected. I opened no other
checkout and no fenced worktree. The `sections/` directory did not exist until I created it, and it
contains only this file. The `docs/topics/` tree was touched only at
`docs/topics/ai-adoption-ladder/design/RESEARCH-product-surface.md:97`, which arrived as a `grep` hit
and is not fenced.
