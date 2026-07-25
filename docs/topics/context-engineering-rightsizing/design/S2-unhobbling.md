# S2 — Unhobbling Claude

Scope: `source-article.md` lines 21–31 (the whole `## Unhobbling Claude` section). Everything below is
verified against the live tree in this working directory or against a page fetched this session; any
claim that is neither is labeled unverified inline.

## Claims

| # | Verbatim source |
|---|---|
| C1 | "Overall, we found that we were over-constraining Claude Code, both through our system prompt and in our CLAUDE.md files and skills." |
| C2 | "For example, when we read transcripts of our own internal usage of Claude Code, we see several conflicting messages in a single request like “leave documentation as appropriate,” or “DO NOT add comments” as our system prompt, skills, and user requests clash with each other." |
| C3 | "Generally, Claude can interpret the user’s intent to get to the right answer, but Claude must think more carefully about these overlapping and conflicting messages before deciding what to do." |
| C4 | "And while these constraints were once needed to avoid worst case scenarios, we have since found we can delete many of them and let the model use surrounding context and judgement instead." |
| C5 | "Additionally, Claude Code now has many more tools." |
| C6 | "Claude used to rely on CLAUDE.md as a source of memory, information, and guidance." |
| C7 | "Now we have memory, artifacts, and skills, which Claude can use to create new ways of loading and sharing context across sessions." |

C2 is deliberately not merged with C3: C2 asserts that conflicts *occur across surfaces within one
request*; C3 asserts a *consequence* (extra deliberation). They are separately checkable and they fail
differently.

## Evidence status

**C1 — UNBACKED as stated; its premise CONFIRMED.**
No official page asserts that Claude Code was over-constrained. That is an internal retrospective
finding about Anthropic's own prompt and is not the kind of thing docs publish. What *is* confirmed is
the premise the claim rests on — that directive text genuinely lives on all three named surfaces
simultaneously: <https://code.claude.com/docs/en/memory> ("CLAUDE.md files are loaded into the context
window at the start of every session") and <https://code.claude.com/docs/en/skills> ("Claude Code loads
a listing of skill names and descriptions into context so Claude knows what's available"). The system
prompt surface is not documented as user-inspectable and I did not verify its contents from any page.

**C2 — UNBACKED as a transcript observation; the underlying failure mode CONFIRMED.**
No page says Anthropic read its own transcripts. But the mechanism the anecdote describes is documented
verbatim at <https://code.claude.com/docs/en/memory>: "**Consistency**: if two rules contradict each
other, Claude may pick one arbitrarily. Review your CLAUDE.md files, nested CLAUDE.md files in
subdirectories, and `.claude/rules/` periodically to remove outdated or conflicting instructions." And
in the troubleshooting section: "Look for conflicting instructions across CLAUDE.md files. If two files
give different guidance for the same behavior, Claude may pick one arbitrarily." Note the doc's scope is
*narrower* than the article's: the doc talks about CLAUDE.md-vs-CLAUDE.md; the article's cross-surface
claim (system prompt × skills × user request) has no doc backing. This gap is load-bearing — see
Conflicts §1.

**C3 — PARTIAL.**
The first half is supported in spirit: <https://code.claude.com/docs/en/memory> states "Claude reads it
and tries to follow it, but there's no guarantee of strict compliance, especially for vague or
conflicting instructions" — which concedes conflicts degrade adherence rather than confirming Claude
reliably reaches the right answer. The second half — that Claude "must think more carefully," i.e. pays
a reasoning cost — is **UNBACKED**. No page I fetched claims a token, latency, or reasoning cost for
conflict resolution. The docs' actual position is bleaker than the article's: arbitrary selection, not
costly-but-correct resolution.

**C4 — UNBACKED.**
Directional advice with no official page behind it. The closest adjacent documented fact is that
`/doctor` "proposes trims for a checked-in CLAUDE.md: it cuts content Claude can derive from the
codebase, such as directory layouts, dependency lists, and architecture overviews, and keeps pitfalls,
rationale, and conventions that differ from tool defaults" (<https://code.claude.com/docs/en/memory>,
requires v2.1.206+). That is a *derivability* trim, not a *constraint deletion* trim — it does not
implement C4. Nothing official sanctions deleting a guardrail in favor of model judgement.

**C5 — PARTIAL (live-environment evidence only).**
<https://code.claude.com/docs/llms.txt> confirms deferred/searchable tooling has its own reference
pages (`tools-reference.md`, `agent-sdk/tool-search.md`); I did not fetch either, so I am not asserting
their contents. Live-environment evidence in this session: the harness exposed a `ToolSearch` tool and
a deferred-tool roster of roughly 300 named entries not loaded at startup. That corroborates "many more
tools" but is environment observation, not documentation.

**C6 — PARTIAL.**
The "used to" framing is unverifiable. The present tense is contradicted in part:
<https://code.claude.com/docs/en/memory> still positions CLAUDE.md as the primary instruction surface
("Use CLAUDE.md files when you want to guide Claude's behavior"). CLAUDE.md's *memory* role is the part
that genuinely moved — see C7.

**C7 — split verdict; this is the most important correction in the section.**

- *memory* — **CONFIRMED**. Auto memory exists, is on by default, is written by Claude, and is loaded
  per session: "Auto memory is on by default"; "The first 200 lines of `MEMORY.md`, or the first 25KB,
  whichever comes first, are loaded at the start of every conversation"
  (<https://code.claude.com/docs/en/memory>).
- *skills* — **CONFIRMED**. "a skill's body loads only when it's used"
  (<https://code.claude.com/docs/en/skills>).
- *artifacts* — **UNBACKED for "loading" context; PARTIAL for "sharing"**.
  <https://code.claude.com/docs/en/artifacts.md> frames artifacts as an *output* surface, titled "Share
  session output as artifacts," and states plainly: "An artifact is a capture of work, not an
  application." Cross-session reference is not automatic and requires the human to supply the URL: "To
  update an artifact from a different session, give Claude the artifact's URL and ask it to revise.
  Without the URL, a new session always creates a new artifact rather than updating an existing one."
  Nothing on that page describes artifacts as a context-loading mechanism. Treating artifacts as a
  memory tier — the reading C7 invites — is not supported by the artifacts documentation.

Tally: CONFIRMED 0 whole claims (2 of C7's 3 sub-mechanisms), PARTIAL 4 (C3, C5, C6, C7), UNBACKED 3
(C1, C2, C4). Per the brief, UNBACKED here is an expected outcome: this section is a retrospective
about an internal prompt, and most of it is not the kind of statement any vendor page would assert.

## Criteria

### Prerequisite: the co-residency model (all criteria below stand on this)

A conflict requires two directives to be *in the same context window at the same time*. Text-shape
matching without this gate produces mostly noise across 181 skills. The load model, verified this
session:

| Surface | When resident | Source |
|---|---|---|
| User-global `~/.claude/CLAUDE.md` | Every session, in full | memory: "loaded in full at launch"; "CLAUDE.md files are loaded in full regardless of length" |
| Repo-root `CLAUDE.md` | Every session in that repo, in full, concatenated *after* user scope | memory: "All discovered files are concatenated into context rather than overriding each other… content is ordered from the filesystem root down to your working directory" |
| Skill **description** (frontmatter) | Every session — **but budget-capped and droppable** | skills: "Claude Code loads a listing of skill names and descriptions into context… if you have many skills, Claude Code shortens descriptions to fit the listing's character budget… The budget scales at 1% of the model's context window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least" |
| Skill **body** (SKILL.md after frontmatter) | Only on invocation, then persists for the session | skills: "full skill content only loads when invoked"; "the rendered `SKILL.md` content enters the conversation as a single message and stays there for the rest of the session" |
| Skill bundled `reference/`, `context/` files | Only when Claude reads them | skills: "letting Claude access detailed reference material only when needed" |
| Agent definition | Subagent context only | sub-agents (not fetched; treated as unverified — see Open questions) |
| Hook output | At the matched lifecycle event | hooks (not fetched; the guardrails hooks' observed behavior this session is empirical, not documentary) |
| Auto memory `MEMORY.md` | Every session, first 200 lines / 25KB | memory |

Two consequences that shape every criterion: **(a)** a skill body can only conflict with another skill
body if both are invoked in one session, so cross-skill-body pairs are *conditional* conflicts, not
guaranteed ones; **(b)** because descriptions are dropped under budget pressure starting with
least-invoked skills, *which* description-layer directives are co-resident is nondeterministic and
history-dependent. A checker must not assume a description it can read on disk is in context.

### Conflict definition (checker-implementable)

Two directives **D1** and **D2** conflict when **all five** hold:

1. **Co-residency** — their surfaces can be simultaneously resident per the table above. Guaranteed
   pairs: any two of {user CLAUDE.md, repo CLAUDE.md, `.claude/rules/*` without `paths`, MEMORY.md}.
   Conditional pairs: anything involving a skill body, a bundled reference file, or a path-scoped rule.
2. **Same observable** — both constrain the *same decidable act*, identified by a (verb, object,
   trigger) triple, not by topic similarity. `AskUserQuestion`-vs-inline-prose is one observable;
   "emoji in a GitHub reaction" and "emoji in user-facing prose" are two.
3. **Opposed polarity** — for at least one input satisfying both triggers, D1's prescribed action and
   D2's prescribed action cannot both be taken. Mandate-vs-prohibition, or two mutually exclusive
   mandated renderings of one act.
4. **No arbitration** — neither directive, nor any third resident text, names which wins. An explicit
   precedence sentence resolves the pair and removes it from the finding set.
5. **Non-vacuous trigger overlap** — a realistic prompt exists that fires both. Guard rails scoped to
   disjoint conditions (interactive vs autonomous session, code vs prose) do not overlap.

Sub-types, by remediation route:

- **Type A — direct contradiction.** Both absolute, opposite polarity. Fix: delete one or arbitrate.
- **Type B — modality collision.** One absolute ("never", "DO NOT"), one conditional ("as appropriate",
  "when warranted"), same act. This is the article's own example shape. Fix: make the absolute
  conditional, or make the conditional's escape hatch explicit. **The highest-yield type**: the absolute
  side reads as a hard rule while the conditional side reads as license, and neither author sees the
  other.
- **Type C — unarbitrated co-authority.** Two surfaces each assert ownership of one decision with no
  precedence statement. Fix: add one precedence sentence at the higher surface.
- **Type D — split-brain.** Two instruction files govern the same behavior but only one is loaded by
  Claude Code, so the divergence is invisible in-session. Fix: import or symlink so both are resident,
  or delete the orphan.

### The criteria

**CRIT-S2-1 (from C2) — Cross-surface polarity collision on one observable.**
*Surfaces*: user-global CLAUDE.md, repo CLAUDE.md, `.claude/rules/*`, SKILL.md body, skill bundled
context/reference files, agent definition, hook `additionalContext`/stderr text.
*Observable*: for each (verb, object, trigger) triple extracted from imperative sentences, the set of
distinct prescribed actions across co-resident surfaces has cardinality > 1 and the actions are
mutually exclusive, and no resident text arbitrates.
*Pass/fail*: FAIL when all five gates in the definition hold.
*Must NOT flag*: `plugins/guardrails/hooks/block-hook-bypass.sh` (blocks `cat > file` and
`echo|printf > file` writes) against the harness Bash guidance "for multi-line strings use a heredoc".
Gate 2 fails — the hook's observable is *writing a file via shell redirection*, the guidance's is
*passing a multi-line string to a command's stdin*. `git commit -F -` heredocs are unaffected, which
`plugins/source-control/skills/commit/SKILL.md` depends on. This pair looks like a conflict on keyword
overlap ("heredoc") and is in fact a correctly-scoped alignment.
*Must NOT flag*: `plugins/source-control/skills/babysit-prs/reference/loop.md:501` ("Never skip emoji
reactions") against a no-emoji output rule — different object (GitHub reaction API call vs assistant
prose).
*Must NOT flag*: an absolute that carries its own exception clause, sitting beside a directive that
presupposes exactly that exception. Live example: `~/.claude/CLAUDE.md:7` "never use the
AskUserQuestion tool **unless explicitly asked to use it**" against `:5` "When asking the user a
question (inline **or via AskUserQuestion**), include your recommendation." Line 5 is surface-agnostic
and is satisfied by line 7's own exception case, so no input prescribes incompatible actions (gate 3
fails) and line 7 arbitrates itself (gate 4 fails). Keyword co-occurrence plus apparent
mandate/prohibition shape makes this the most tempting false positive in the repo's instruction set.

**CRIT-S2-2 (from C2, Type B) — Absolute modality with no stated exception on a judgement-bearing act.**
*Surface*: any resident instruction file.
*Observable*: a sentence containing `never|always|must|DO NOT|ALL|ANY|every` whose object is an act
whose correctness is context-dependent (writing a comment, expanding scope, choosing an output
rendering, deciding to ask), and which states no exception clause and no precedence rule.
*Pass/fail*: FLAG for review, not auto-fail — this is a review queue, not a defect.
*Must NOT flag*: absolutes over acts with genuinely no correct exception, e.g.
`CLAUDE.md:46` "No PII / secrets. Git history is durable: scrub before the first commit, not after," or
the surgical-staging rule "Never `git add -A` or `git add .`" (`AGENTS.md:20`). Safety-critical
irreversibles are exactly where the article itself concedes constraints stay ("Avoid making them
overconstrained, **except in highly important areas**", line 105).

**CRIT-S2-3 (from C7) — CLAUDE.md content that belongs on a lower-cost tier.**
*Surface*: CLAUDE.md, `.claude/rules/*` without `paths`.
*Observable*: a block that is (a) a multi-step procedure rather than a standing fact, (b) reference
material only some tasks need, or (c) derivable by reading the repo. Official routing:
"If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill
or a path-scoped rule instead" (<https://code.claude.com/docs/en/memory>).
*Pass/fail*: FAIL when a CLAUDE.md block is a numbered/sequenced procedure, or exceeds ~10 lines on a
topic that fires for a minority of sessions.
*Must NOT flag*: a gotcha stated as a fact with no procedure attached — e.g. `CLAUDE.md:44-45`
("Installed plugins run from an isolated cache — reference only files inside the plugin via
`${CLAUDE_PLUGIN_ROOT}`"). That is a pitfall that cannot be derived by reading the tree and must be
resident before Claude writes the first path.

**CRIT-S2-4 (from C7) — "artifact" used as a context-loading tier.**
*Surface*: any repo doc, skill, or plan that names artifacts as a memory/context mechanism.
*Observable*: text asserting or implying that a published claude.ai Artifact is read back as context in
a later session without the human supplying its URL.
*Pass/fail*: FAIL — contradicted by <https://code.claude.com/docs/en/artifacts.md> ("Without the URL, a
new session always creates a new artifact rather than updating an existing one").
*Must NOT flag*: `docs/PLUGIN-ARTIFACT-PROTOCOL.md`. Its "artifact" is a repo-file lifecycle artifact,
an entirely different referent from the article's; it never claims cross-session auto-loading. This is
the section's sharpest false-positive trap and any checker must disambiguate the word.

**CRIT-S2-5 (from C1, Type D) — Orphaned instruction file.**
*Surface*: repo root.
*Observable*: an `AGENTS.md` (or equivalent agent-facing instruction file) exists, is not a symlink to
`CLAUDE.md`, and no `@AGENTS.md` import appears in `CLAUDE.md`. Official remedy:
"Claude Code reads `CLAUDE.md`, not `AGENTS.md`. If your repository already uses `AGENTS.md` for other
coding agents, create a `CLAUDE.md` that imports it" (<https://code.claude.com/docs/en/memory>).
*Pass/fail*: FAIL.
*Must NOT flag*: a repo with `AGENTS.md` and no `CLAUDE.md` — nothing is split-brained there.

## Targets in this repo

Populations, measured by command (run in `<repo-root>`):

| Population | Command | Count |
|---|---|---|
| Skills at the canonical path | `ls plugins/*/skills/*/SKILL.md` | **181** |
| All `SKILL.md` including vendored upstream copies | `find plugins -name SKILL.md` | **187** |
| Vendored (the 6-file delta) | `find plugins -name SKILL.md \| grep -v '^plugins/[^/]*/skills/[^/]*/SKILL.md$'` | **6** |
| Plugins | `ls plugins` | **60** |
| Agent definitions | `find . -path '*/agents/*.md' -not -path './.git/*'` | **7** |
| `hooks.json` files | `find . -name hooks.json -not -path './.git/*'` | **15** |
| `CLAUDE.md` files in-tree | `find . -name CLAUDE.md -not -path './.git/*'` | **1** (`./CLAUDE.md`) |
| Total chars of skill `description` frontmatter | script over the 181 | **104,760** |
| Skills with `disable-model-invocation: true` (description withheld from listing) | script | **51** |
| Skills whose description is therefore expected in the listing | 181 − 51 | **130** |

The brief's "~181 skills" matches the canonical-path count exactly; my initial 187 counted six vendored
upstream `SKILL.md` copies nested under `skills/*/vendor/` and `skills/*/vendor/*/`.

### FINDING 1 — a real, unarbitrated conflict over one observable (CRIT-S2-1)

**Observable**: how a skill renders a bounded set of options to the user — the `AskUserQuestion` card
versus numbered inline prose.

**Measurement.** 61 lines across `plugins/**/*.md` (excluding CHANGELOGs) mention `AskUserQuestion`; 11
carry the `use_ask_user_question` gate on the same line, 50 do not. Manual adjudication of the 50 removes
3 `planning` sites — `skills/interview/SKILL.md:79` (gated by adjacent prose: "inline prose rounds by
default, `AskUserQuestion` only when the user opted in and the round qualifies"),
`skills/interview/SKILL.md:119` and `skills/setup/SKILL.md:124` (descriptive, not mandates; the gate sits
on `setup/SKILL.md:122`). **Adjudicated: 47 ungated mandate sites across 9 plugins.**

| Plugin | Ungated sites | Sharpest instance |
|---|---|---|
| `repo-hygiene` | 18 | `plugins/repo-hygiene/skills/clean/SKILL.md:156` — "**Mandatory gate:** show dry-run output → `AskUserQuestion` → only then `--apply`." |
| `docs-hygiene` | 13 | `plugins/docs-hygiene/skills/rename-references/context/triage.md:63` — "present each match individually via `AskUserQuestion`… **Always one-by-one** — batched confirmation defeats the safety purpose." |
| `claude-ops` | 4 | `plugins/claude-ops/skills/plugins/context/sync.md:86` |
| `disk-hygiene` | 3 | `plugins/disk-hygiene/skills/clean/SKILL.md:196` — "Use `AskUserQuestion` to ask whether to remove **exactly that** …" |
| `event-storming` | 3 | `plugins/event-storming/skills/simulation/SKILL.md:80` |
| `implementation` | 3 | `plugins/implementation/skills/implement/SKILL.md:131` — "Surface to the user with category tag + `AskUserQuestion`. NEVER batch…" |
| `bug-report` | 1 | `plugins/bug-report/skills/write/SKILL.md:66` — "Use `AskUserQuestion` when 2-4 named options exist" |
| `source-control` | 1 | `plugins/source-control/skills/babysit-loop/SKILL.md:83` |
| `planning` | 1 | `plugins/planning/skills/plan/SKILL.md:69` — "The user may override via `AskUserQuestion` only when they explicitly accept skipping design exploration" (gated on *what* may be overridden, not on `use_ask_user_question`) |

The finding splits by audience, because remediation routes differ.

#### 1a — repo-internal, Type C (unarbitrated co-authority), fixable entirely inside `plugins/`

`plugins/planning/.claude-plugin/plugin.json:6-11` declares a `use_ask_user_question` boolean with
`"default": false` and the rationale "Default: inline prose (dictation-friendly)," and the planning
skills condition on it — e.g. `plugins/planning/skills/interview/context/gotchas.md:9`: "`AskUserQuestion`
without the opt-in, or beyond its cap — the card surface requires the `use_ask_user_question` user config
AND a round of ≤4 mutually independent questions. Prose otherwise; when in doubt, prose." Eight other
plugins mandate the card with no gate at all. Both sides are in-repo; no marketplace-wide convention,
`docs/PLUGIN-PHILOSOPHY.md` rule, or repo `CLAUDE.md` line arbitrates which shape governs.

`planning/skills/plan/SKILL.md:69` makes this airtight: the plugin that *owns* the opt-in has a site that
bypasses its own gate. The inconsistency is not merely cross-plugin, it is intra-plugin.

This is the "at least one real instance in this repo" the section owes. **Route: repo change.**

#### 1b — cross-audience, Type A, requiring a user-global change I cannot make

`~/.claude/CLAUDE.md:7` — "Ask questions inline; never use the AskUserQuestion tool
unless explicitly asked to use it." That is resident in every session. All 47 ungated sites contradict
it the moment their skill is invoked.

**Why this satisfies all five gates.** Co-residency: user CLAUDE.md is resident in every session; each
skill body becomes resident the moment that skill is invoked (gate 1, conditional pair). Same
observable: rendering a bounded option set to the user (gate 2). Opposed polarity: "never use the
AskUserQuestion tool" vs "**Mandatory gate:** … `AskUserQuestion`" — both cannot be obeyed (gate 3). No
arbitration: nothing in `plugins/repo-hygiene/**`, `plugins/disk-hygiene/**`, the repo `CLAUDE.md`, or
the user CLAUDE.md states which wins (gate 4). Trigger overlap: `/repo-hygiene:clean` in an interactive
session fires both (gate 5). Note gate 4 turns on line 7's exception being *unreachable in practice* —
"unless explicitly asked" is satisfied by the user, never by a skill, so an invoked skill's mandate has
no path through it.

**Why it matters more than a style nit.** In `repo-hygiene:clean` and `disk-hygiene:clean` the
`AskUserQuestion` call *is* the destructive-action confirmation gate. Resolving the conflict toward the
user CLAUDE.md degrades a safety mechanism; resolving it toward the skill disobeys a standing user
instruction. That is the article's failure mode with real stakes attached, not a rendering preference.
**Route: recommendation to the chezmoi-managed user-global surface; read-only to me.**

### FINDING 2 — Type D split-brain (CRIT-S2-5)

`AGENTS.md` exists at repo root (1,261 bytes, a regular file, not a symlink — verified via `ls -la`).
`CLAUDE.md` contains **zero** `@` import directives (verified: `grep -n '@' CLAUDE.md` returns nothing).
Per <https://code.claude.com/docs/en/memory>, Claude Code therefore never loads `AGENTS.md`.

Three rules live only there and are invisible to Claude Code in-session:

- `AGENTS.md:9-16` — synced standards files are overwritten by the next sync; fix upstream, never patch
  the materialized copy. (The repo `CLAUDE.md` does not carry this; the user-global CLAUDE.md carries a
  related but differently-worded sync-manifest rule.)
- `AGENTS.md:18-22` — "Stage the specific files a change touches. Never `git add -A` or `git add .`".
  Claude Code sees this rule only when `source-control:commit` is invoked, which independently restates
  it (`plugins/source-control/skills/commit/SKILL.md:3`, description) — duplication that will drift.
- `AGENTS.md:24-28` — PR title convention, near-duplicating `CLAUDE.md:59-63`. Duplicated today,
  divergent tomorrow.

This is not yet a contradiction, so it is not a CRIT-S2-1 finding; it is the precursor. It matters here
specifically because this repo ships a `codex` plugin that hands work to Codex CLI, which *does* read
`AGENTS.md` — so two agents working the same repo operate under two different rule sets.

### FINDING 3 — the description budget makes co-residency nondeterministic (bears on CRIT-S2-1 gate 1)

104,760 characters of `description` frontmatter across 181 skills, of which 130 expect listing
placement. Official behavior: "The budget scales at 1% of the model's context window. When the listing
overflows, Claude Code drops descriptions starting with the skills you invoke least"
(<https://code.claude.com/docs/en/skills>).

Empirically observed in this session: `bug-report:write`, `adhd:clarify`, `architecture:improve`,
`review:fanout`, and `planning:brainstorm` all carry `disable-model-invocation: false` (verified in
their frontmatter) and therefore *should* appear with descriptions — but appeared **name-only** in the
skill listing this session, while `source-control:commit` appeared with its full description. That is
budget-driven description dropping, observed live.

Consequence for this section: a conflict checker cannot treat the description layer as reliably
resident. It also converts C1 from an aesthetic point into a measurable one — a large fraction of the
104,760 characters this repo authors as always-resident routing text is not reaching the model.

### Candidate targets for the remaining criteria (populations, not adjudicated findings)

- **CRIT-S2-2**: `rg -c 'Never |NEVER |Always |must not' plugins/**/SKILL.md` is the queue. The repo
  `CLAUDE.md:6-11` fresh-docs mandate is the highest-value single entry — see Conflicts §3.
- **CRIT-S2-3**: repo `CLAUDE.md` is 63 lines, well under the 200-line target, and already routes detail
  to `docs/PLUGIN-PHILOSOPHY.md` and `docs/MIGRATION-PLAYBOOK.md` (`CLAUDE.md:52-57`). It largely passes.
  The exception is the 18-row fresh-docs URL table (`CLAUDE.md:13-30`), which is reference material, not
  a standing fact.
- **CRIT-S2-4**: I grepped `docs/` and `plugins/` for artifact-as-memory framing and found none.
  `docs/PLUGIN-ARTIFACT-PROTOCOL.md` uses a different referent entirely (repo lifecycle files). **Absence
  finding: looked, found none.**

## Conflicts and ambiguity

**1. The article's conflict claim is broader than any documented behavior, and the gap is the whole
problem.** Official docs describe conflict only *within* the CLAUDE.md family
(<https://code.claude.com/docs/en/memory>: "Look for conflicting instructions across CLAUDE.md files").
C2's cross-surface claim — system prompt × skills × user request — has no documented mechanism, no
tooling, and no diagnostic. `/doctor` reports CLAUDE.md derivability trims and skill-listing context
cost; nothing I fetched says it detects a skill-body-vs-CLAUDE.md contradiction. So the article names a
failure mode the product does not yet help you find. Finding 1 exists precisely because nothing would
have caught it.

**2. This user's demonstrated remedy for cross-surface conflict is to ADD arbitration text; the
article's remedy is to DELETE constraints. These are opposite moves, and this repo has already chosen.**
Three instances, all in-tree or in the user's own global file:

- `~/.claude/CLAUDE.md:39` resolves the review-severity vocabulary collision by writing a paragraph
  declaring which vocabulary governs which output shape and asserting "the two cover different output
  shapes, so no conflict."
- `~/.claude/CLAUDE.md:43` declares "a target repository's own documented convention (CLAUDE.md,
  CONTRIBUTING, standards) wins over the harness default" — an explicit precedence sentence written to
  settle the commit-trailer collision.
- `plugins/guardrails/hooks/block-noncanonical-commit.sh:11-13` carries the matching engineering
  decision in a comment: "WHY NOT `--trailer`: the trailer is POLICY, not mechanic. /commit itself omits
  it when the resolved `trailer_policy` is `none`, and a repo whose convention forbids a co-author
  trailer is a documented, supported case."

Every one of those is *more* text on *more* surfaces — the correct engineering move under the current
docs (the memory page's own advice is to remove conflicts, and a precedence sentence is the cheapest
way to do that without losing a rule), and the exact opposite of C4's "delete many of them." Applying C4
naively to this repo would strip the arbitration text and reintroduce the conflicts it was written to
settle. **An operator decision is required here and I flag it rather than resolve it.**

**3. C4 collides head-on with this repo's single most deliberate constraint.** Repo `CLAUDE.md:6-11`:
"## Fresh-docs mandate (non-negotiable) — Operate only off current official documentation… Before ANY
change to this repo (a new plugin, a manifest edit, a structure change), WebFetch the relevant page(s)
below." By CRIT-S2-2 this is a textbook over-broad absolute: "ANY change" makes a typo fix require a
doc fetch, and the article's own diagnosis ("for a certain subset of prompts, this guidance would be
wrong," line 44) applies verbatim. But it is also the rule the repo's own header calls
**non-negotiable**, and it exists because plugin schemas move faster than training data — the exact
worst-case-avoidance rationale C4 says is now obsolete. C4 does not distinguish a stale guardrail from a
live one. My read: the mandate's *scope* is over-broad (mechanical edits that touch no schema), its
*substance* is not deletable. That is a scope narrowing, not a deletion — a third option C4 does not
offer.

**4. C7 does not generalize: artifacts are not a context tier.** The article lists memory, artifacts,
and skills as one class of mechanisms "Claude can use to create new ways of loading and sharing context
across sessions." The artifacts documentation supports *sharing* and explicitly does not support
*loading*: an artifact is "a capture of work, not an application," and a later session cannot find it
without a human-supplied URL. Skills and memory auto-load; artifacts do not. Anyone reading C7 as
license to move context into artifacts will lose it.

**5. C3 understates the failure.** The article says Claude "must think more carefully… before deciding
what to do," implying a resolved-but-costlier path. The memory docs say "Claude may pick one
arbitrarily" — twice. The doc position is that the outcome is *nondeterministic*, not merely expensive.
For criteria design this matters: a conflict is a correctness defect, not a token-efficiency defect, and
should not be triaged by token cost.

**6. A harness/orchestration instance of the same failure mode occurred while producing this file.** My
subagent system prompt carries "Do NOT Write report/summary/findings/analysis .md files. Return findings
directly as your final assistant message"; the task instruction that dispatched me orders "Write
`sections/S2-unhobbling.md`." Same observable (whether to write a findings markdown file), opposed
polarity, no arbitration. Documented here as an instance, not as a repo finding — it lives in the
harness, not in `plugins/`. Resolved toward the explicit task instruction: the file exists, and the
compressed summary is also returned in the final message.

**7. Scope note on C1.** I verified the CLAUDE.md and skills legs of "system prompt AND CLAUDE.md AND
skills." The system-prompt leg I cannot verify — no official page publishes Claude Code's system prompt,
and I did not treat my own harness prompt as documentation. Any criterion targeting the system prompt
surface is out of reach for a repo-level checker and belongs to `--append-system-prompt` /
`managed-settings.json` `claudeMd`, which are the only user-writable system-adjacent surfaces the docs
name.

## Open questions for the operator

- Finding 1a (**route: repo change**): does the marketplace adopt one question-rendering convention?
  **RECOMMENDED: yes — promote `planning`'s shape to a marketplace-wide rule in
  `docs/PLUGIN-PHILOSOPHY.md` (every `AskUserQuestion` site gates on a per-plugin opt-in, default off)
  and bring the 47 ungated sites, including `planning/skills/plan/SKILL.md:69`, in line.** One plugin
  already proves the pattern, and it preserves the destructive-action gates in
  `repo-hygiene`/`disk-hygiene` rather than deleting them.
- Finding 1b (**route: user-global recommendation, read-only to me**): keep `~/.claude/CLAUDE.md:7` as
  an absolute prohibition? **RECOMMENDED: restate it as a default-off preference that names the
  per-plugin opt-in as the sanctioned exception**, so an invoked skill has a reachable path through it.
  As written, "unless explicitly asked to use it" can only be satisfied by the user, never by a skill,
  which is what makes 1b a hard contradiction rather than a soft default.
- Finding 2: import or delete? **RECOMMENDED: add `@AGENTS.md` as the first line of `CLAUDE.md` and
  delete the duplicated PR-convention block from `CLAUDE.md:59-63`**, per the official remedy. Symlink is
  not viable — this is a Windows machine and the docs note symlink creation needs Administrator or
  Developer Mode.
- Does §2's add-arbitration posture stay, or does the article's delete-constraints posture win?
  **RECOMMENDED: keep arbitration; adopt C4 only where a constraint has no current safety rationale.**
  This is a values call about the repo's operating philosophy and I decline to make it unilaterally.
- Should the fresh-docs mandate's "ANY change" be narrowed? **RECOMMENDED: yes — scope it to changes
  touching a plugin manifest, marketplace schema, hook contract, or documented harness behavior**,
  leaving prose and mechanical edits out. Non-negotiable substance, negotiable scope.
- Finding 3: raise `skillListingBudgetFraction`, or trim descriptions? **RECOMMENDED: trim first.**
  Raising the budget spends context to preserve text that CRIT-S2-3's logic says is over-long anyway;
  this overlaps other sections' territory and should be reconciled with them before acting.
- Should a conflict checker ship as a plugin here? **RECOMMENDED: yes, but only Types A/C/D initially** —
  Type B is a review queue with an irreducible judgement step and will generate false positives until
  the safety-critical allowlist is curated.

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, the
`context-engineering-claude-5` or `fable-field-guide-audit` worktrees, any other checkout of this
repository, or any other agent's file under `sections/`. `docs/topics/` was listed once as a bare
directory name in a top-level `ls docs/` and was not entered. Every repo search I ran was scoped to
`plugins/`, `docs/` non-topic files, or the repo root. I did read line ranges of
`plugins/playbooks/skills/fable-5/context/*.md` — a shipped plugin, not on the fence list and not the
fenced `fable-field-guide-audit` material — as a discarded secondary conflict candidate.
