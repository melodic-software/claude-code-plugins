# S5 — Then: Put it all upfront / Now: Use progressive disclosure

All doc quotes were fetched this session via WebFetch. All repo numbers come from commands run
against `D:/repos/.worktrees/context-engineering-rightsizing`.

**Reproducing the measurements.** Shell one-liners are inline where they suffice. Every derived
figure (listing chars, per-plugin subtotals, body sizes, reachability) comes from one script,
written this session to
`C:/Users/KYLESE~1/AppData/Local/Temp/claude/C--Users-KyleSexton/bd852ada-71dd-41c9-abaf-972d4f4f8363/scratchpad/s5-measure.mjs`,
run as `node s5-measure.mjs D:/repos/.worktrees/context-engineering-rightsizing`. That path is a
session scratchpad and **will not persist**. Its method, sufficient to rebuild: parse each
`plugins/*/skills/*/SKILL.md`; treat everything after the closing frontmatter `---` as the *body*
(all body figures below are post-frontmatter); read `description` and `when_to_use` as
whitespace-collapsed scalars; partition on `disable-model-invocation: true`; and compute support-file
reachability by BFS from the body through every `.md` under the skill directory it names by relative
path or basename, excluding `evals/`, `scripts/`, `tests/`. If criteria C5.2 and C5.3 are adopted, a
durable version belongs in this repo's `scripts/` alongside the existing skill checks — see open
question 4.

## Claims

1. **Crucial-but-intermittent content used to ride in the system prompt.**
   > "Because Claude Code was focused on coding, our system prompt included detailed information on
   > how to do code review and verification. These were not always needed, but when they were, it
   > was crucial information."

2. **The harness is now competent at progressive disclosure.**
   > "Since then, Claude Code has gotten very competent at using progressive disclosure- loading the
   > right context at the right times."

3. **Verification and code review became selectively-callable skills.**
   > "For example, we moved verification and code review into their own skills that Claude Code
   > could selectively call."

4. **Progressive disclosure also applies to tools, via deferred loading and `ToolSearch`.**
   > "But progressive disclosure is not just for skills, we also use it for tools. Some of our tools
   > are 'deferred loading,' which means the agent must search for their full definitions using
   > ToolSearch before using them."

5. **Deferred tools let a harness carry more tools without paying context for them.**
   > "This allows us to have more tools (such as our Task tools) that don't take up context until
   > they're needed."

6. **The same technique transfers to user-authored CLAUDE.md and SKILL.md.**
   > "The same can be applied to your own CLAUDE.md and Skill.md files."

7. **Myth-bust: these files should not be a central repository of everything you might need.**
   > "A common myth is that you want to make these a central repository for every known practice
   > that you *might* run into, because Claude would not find it otherwise."

8. **The prescription is a tree of files loaded at the right time.**
   > "Instead, consider having a tree of files that can be loaded at the right time."

Corroborating lines elsewhere in the article (owned by the "Applying this to your context" section,
cited here only because they restate claim 8): line 102 "create a verification skill and reference
it from your CLAUDE.md", line 107 "For long skills, try and use progressive disclosure as much as
possible- divide it into many files and split them out."

## Evidence status

| # | Status | Basis |
|---|--------|-------|
| 1 | **UNBACKED** | No official page describes the historical contents of Claude Code's system prompt. The system prompt is undocumented by design — <https://code.claude.com/docs/en/context-window.md> lists it as `vis: 'hidden'`, "Core instructions for behavior, tool use, and response formatting. Always loaded first. You never see it." Unverifiable and unfalsifiable from outside; treat as author testimony. |
| 2 | **PARTIAL** | The *mechanisms* are documented in detail (see the taxonomy below). The *claim of competence* is a model-capability assertion no doc makes. |
| 3 | **CONFIRMED** | <https://code.claude.com/docs/en/skills.md>: "Claude Code includes a set of bundled skills, such as `/doctor`, `/code-review`, `/batch`, `/debug`, `/loop`, and `/claude-api`." <https://code.claude.com/docs/en/sub-agents.md>: "This includes the bundled `/verify` and `/code-review` skills: only you can run them". Both exist as skills; both are `disable-model-invocation`-equivalent (user-invoked only). |
| 4 | **CONFIRMED** | <https://code.claude.com/docs/en/agent-sdk/tool-search.md>: "When tool search is active, tool definitions are withheld from the context window. The agent receives a summary of available tools and searches for relevant ones when the task requires a capability not already loaded." "Tool search is enabled by default." |
| 5 | **CONFIRMED, with numbers** | Same page: "Tool definitions can consume large portions of the context window (50 tools can use 10-20K tokens)"; "Tool selection accuracy degrades with more than 30-50 tools loaded at once"; "**Maximum tools:** 10,000 tools in your catalog"; "returns up to five most relevant tools per search by default". <https://code.claude.com/docs/en/context-window.md> shows "MCP tools (deferred)" at `tokens: 120` for the name list. |
| 6 | **PARTIAL — and this is where the article is dangerously imprecise** | "The same can be applied to your own CLAUDE.md and Skill.md files" is true for SKILL.md and **false for the most obvious CLAUDE.md reading**. The one splitting mechanism a reader is most likely to reach for — `@path` imports — explicitly does not defer. See the taxonomy. |
| 7 | **CONFIRMED** | <https://code.claude.com/docs/en/memory.md>: "Keep it to facts Claude should hold in every session… If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill or a path-scoped rule instead." "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." <https://code.claude.com/docs/en/skills.md>: "Keep the body itself concise. Once a skill loads, its content stays in context across turns, so every line is a recurring token cost." |
| 8 | **PARTIAL** — confirmed for skills, conditional for CLAUDE.md | skills.md: "Skills can include multiple files in their directory… Large reference docs, API specifications, or example collections don't need to load into context every time the skill runs." Tip: "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files." For CLAUDE.md the "tree" only works if the branch is a genuinely deferring destination. |

### The deferral taxonomy — verified per destination

This is the load-bearing table. Every split remediation this repo proposes must name a destination
from the first block.

**Defers (context paid only when the trigger fires)**

| Destination | Trigger | Verbatim basis |
|---|---|---|
| `SKILL.md` body | Skill invoked (by user or model) | skills.md: "Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it." |
| Skill support files named from the body | Claude reads the file | skills.md: "This keeps `SKILL.md` focused on the essentials while letting Claude access detailed reference material only when needed." |
| Nested `CLAUDE.md` / `CLAUDE.local.md` **below** cwd | Claude reads a file in that subdirectory | memory.md: "Claude also discovers `CLAUDE.md` and `CLAUDE.local.md` files in subdirectories under your current working directory. Instead of loading them at launch, they are included when Claude reads files in those subdirectories." |
| `.claude/rules/*.md` **with** `paths:` frontmatter | Claude reads a matching file | memory.md: "These conditional rules only apply when Claude is working with files matching the specified patterns." "Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use." |
| Skill frontmatter `paths:` | Working with matching files | skills.md: "Glob patterns that limit when this skill is activated… When set, Claude loads the skill automatically only when working with files matching the patterns." |
| Auto-memory topic files | Claude reads them | memory.md: "Topic files like `debugging.md` or `patterns.md` are not loaded at startup. Claude reads them on demand using its standard file tools when it needs the information." |
| Deferred tool definitions | `ToolSearch` call | tool-search.md, quoted above. |
| A skill with `disable-model-invocation: true` | User types `/name` | context-window.md: "Skills with `disable-model-invocation: true` are not in this list. They stay completely out of context until you invoke them with `/name`." |
| Nested `.claude/skills/` below cwd | Claude reads/edits a file in that subdirectory | skills.md: "When Claude reads or edits a file in a subdirectory, skills from that subdirectory's `.claude/skills/` become available." |

**Does NOT defer — splitting here is the no-op that looks like a fix**

| Destination | Verbatim basis |
|---|---|
| `@path` imports from CLAUDE.md | memory.md: "Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them." And, explicitly as a myth-bust: "You can also split content into imports for organization, **though imported files still load and enter the context window at launch**." And again: "Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch." |
| `.claude/rules/*.md` **without** `paths:` | memory.md: "Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`." |
| `CLAUDE.md` / `CLAUDE.local.md` at or above cwd | memory.md: "CLAUDE.md and CLAUDE.local.md files in the directory hierarchy above the working directory are loaded in full at launch." |
| The skill listing (name + description + `when_to_use`) | skills.md: "Claude Code loads a listing of skill names and descriptions into context so Claude knows what's available. The listing always contains every skill name". **There is no tree here.** The only levers are trimming the text, `disable-model-invocation`, or not shipping the skill. |
| Splitting one skill into several skills | Each new skill adds a listing entry — it *moves* cost from the deferred tier to the always-loaded tier. |

**Eager at invocation — the opposite of deferral, easily mistaken for it**

| Mechanism | Verbatim basis |
|---|---|
| `` !`command` `` injection in a SKILL.md body | skills.md: "The `` !`<command>` `` syntax runs shell commands **before the skill content is sent to Claude**. The command output replaces the placeholder, so Claude receives actual data, not the command itself." Output size is unbounded and paid on every invocation. |
| Subagent `skills:` frontmatter preload | sub-agents.md: "The full content of each listed skill is injected into the subagent's context at startup." |

**Not a context mechanism at all (do not propose these as deferral)**

- `relevance` in `marketplace.json` — gates *install suggestions* only.
  <https://code.claude.com/docs/en/plugin-relevance.md>: "Claude Code surfaces an install suggestion
  for that plugin." Nothing about loading.
- `skillOverrides` — **cannot touch plugin skills.** skills.md: "Plugin skills are not affected by
  `skillOverrides`. Manage those through `/plugin` instead."

**Absence finding.** No official page states that a `SKILL.md` body supports `@path` expansion. I
read the full <https://code.claude.com/docs/en/skills.md> and <https://code.claude.com/docs/en/memory.md>;
`@path` import is documented exclusively as a CLAUDE.md/memory feature, and skills.md shows plain
relative markdown links (`[reference.md](reference.md)`) for support files. **Do not assume a
`@file` reference inside a SKILL.md expands.** This repo has zero such references today
(`grep -rnoE '(^|[[:space:]])@[A-Za-z0-9_./~-]+\.md' plugins/*/skills/*/SKILL.md` → no matches), so
it is a forward-looking guard, not a current defect.

### Two harness limits the article does not mention, both directly about this section

1. **The compaction re-attach caps truncate and then evict skill bodies.** skills.md: "When the
   conversation is summarized to free context, Claude Code re-attaches the most recent invocation of
   each skill after the summary, **keeping the first 5,000 tokens of each**. Re-attached skills share
   a combined budget of 25,000 tokens. Claude Code fills this budget starting from the most recently
   invoked skill, so **older skills can be dropped entirely after compaction** if you have invoked
   many in one session." Two distinct failures: a body above ~5,000 tokens has its tail silently
   discarded, and the 25,000-token *shared* budget means a chain of large skills evicts its own
   earlier members. The shared budget binds harder: **it holds only five skills that sit at the
   5,000-token per-skill cap**, and this repo has **13 bodies at or above that cap** (measured
   below). Any workflow chaining six of them evicts its own earlier members — and this repo composes
   exactly that way: `re-anchor:sweep-all-disciplines` routes across sibling correctors, and the
   plan → design → implement → review chains invoke four or more heavy skills in sequence.
   Progressive disclosure stops being a style preference at that line; the harness enforces it.

2. **The skill listing does not survive compaction.** context-window.md, on the "Skill descriptions"
   block: "Unlike the rest of the startup content, this listing is not re-injected after `/compact`.
   Only skills you actually invoked get preserved." Discovery degrades over a long session in a way
   CLAUDE.md does not (memory.md: "Project-root CLAUDE.md survives compaction").

3. **CLAUDE.md is multiplied by every subagent.** sub-agents.md, "What loads at startup": a non-fork
   subagent's initial context contains "**CLAUDE.md files**: every level of the CLAUDE.md hierarchy
   the main conversation loads… The built-in Explore and Plan agents skip this." Every byte in
   CLAUDE.md is paid again per spawned agent. This repo's skills fan out heavily, so CLAUDE.md
   trimming has a multiplier the article never names.

## Criteria

### C5.1 — A split remediation must name a deferring destination *(highest leverage)*

- **Surface**: any proposed remediation, plan, or PLAN.md/spec artifact in this effort that says
  "split", "move to a separate file", "extract", or "break up".
- **Observable**: the proposal names a destination that appears in the *Defers* block above. A
  proposal that moves content to a `@path` import, to a `.claude/rules/*.md` without `paths:`
  frontmatter, or to another CLAUDE.md at or above cwd **fails**, because measured context is
  unchanged.
- **Must NOT flag**: a split explicitly justified as *organizational* — "split for maintainer
  readability, context cost unchanged" — where the artifact says so. Organization is a legitimate
  goal; silently claiming a context win is the defect.

### C5.2 — SKILL.md body must fit the compaction re-attach cap

- **Surface**: `plugins/*/skills/*/SKILL.md` body (post-frontmatter).
- **Observable**: post-frontmatter body ≤ ~5,000 tokens. Proxy: ≤ 20,000 bytes at a nominal
  4 chars/token; the band across 3.5–4.5 chars/token is 17,500–22,500 bytes. **State this as a
  proxy** — I had no tokenizer in-environment, so cases inside the band are unresolved and the
  population count moves with the assumption (20 / 13 / 11 at 3.5 / 4.0 / 4.5). Over the cap, cite
  skills.md's re-attach language: content past 5,000 tokens is dropped after compaction.
- **Second observable, on workflows rather than files**: a documented chain that invokes **five or
  more** at-or-above-cap skills, which fills the 25,000-token *shared* re-attach budget and evicts
  the earliest members. This is the binding constraint here and it is not visible from any single
  file.
- **Must NOT flag**: a skill whose *support tree* is large. `tdd:principles` (4,997-byte body,
  141,468 bytes of support `.md`, 28.3x) is the exemplar of the correct shape, not a violation.

### C5.3 — Support files must be transitively reachable from SKILL.md

- **Surface**: `.md` files under a skill directory, excluding `evals/`, `scripts/`, `tests/`.
- **Observable**: reachable by BFS from `SKILL.md` — the body names the file (relative path or
  basename), or names an intermediate support file that names it, transitively. Unreachable means
  it is not deferred, it is *dead*: the model has no path to discover it.
- **Must NOT flag**: (a) depth > 1 — an index file that fans out to a subdirectory is the intended
  tree shape; (b) `evals/` fixtures, which are test inputs and never enter context; (c) `scripts/`,
  which skills.md describes as "utility script (executed, not loaded)"; (d) a `templates/` file
  named only by a glob or pattern in the body rather than by literal filename — verify by reading
  before flagging.

### C5.4 — Description text is always-loaded and must be budgeted as such

- **Surface**: `description` + `when_to_use` in `plugins/*/skills/*/SKILL.md` frontmatter, for
  skills that do **not** set `disable-model-invocation: true`.
- **Observable**: this text is in context in every session that enables the plugin, before any skill
  is invoked, and it is the one tier no tree can defer. Because `/plugin` toggles whole plugins and
  `skillOverrides` cannot reach plugin skills (Conflict 4), assess it as a **per-plugin subtotal**,
  not as a per-skill or marketplace-wide number. Flag a plugin whose subtotal is disproportionate to
  its skill count, and any entry long enough that overflow-dropping could remove it wholesale —
  skills.md: "When the listing overflows, Claude Code drops descriptions starting with the skills
  you invoke least." Do **not** flag against an absolute budget figure: the two official figures
  disagree by an order of magnitude and their unit is unstated (Conflict 1).
- **Must NOT flag**: a long description that is *dense with trigger keywords*. skills.md's own
  guidance is "Check the description includes keywords users would naturally say" and "Put the key
  use case first". Trimming a description into vagueness trades a context win for a discovery loss.
  The criterion is about front-loading and redundancy, not raw length.

### C5.5 — `disable-model-invocation: true` is the only zero-cost listing tier

- **Surface**: skill frontmatter.
- **Observable**: a skill that is genuinely only ever user-invoked (setup, one-shot operational
  commands) and that does *not* set `disable-model-invocation: true` is paying always-loaded
  description cost for nothing.
- **Must NOT flag**: any skill intended for model auto-invocation, and any skill intended to be
  preloaded into a subagent — sub-agents.md: "You can't preload skills that set
  `disable-model-invocation: true`, since preloading draws from the same set of skills Claude can
  invoke." The flag is only valid where model invocation is genuinely unwanted.

### C5.6 — `` !`cmd` `` injection is eager and unbounded

- **Surface**: `plugins/*/skills/*/SKILL.md` bodies containing `` !` ``.
- **Observable**: each injection runs before the skill content is sent and its output is pasted into
  the message. Flag an injection whose output has no bound (e.g. an unpaged `git log`, a full `gh pr
  diff`, a recursive listing) — that is anti-deferral inside a skill that otherwise looks tidy.
- **Must NOT flag**: injections with intrinsically bounded output (`git rev-parse`, `node --version`,
  a `--porcelain` status, a script that self-limits). Count alone is not the signal; output bound is.

### C5.7 — CLAUDE.md carries a per-subagent multiplier

- **Surface**: repo `CLAUDE.md`, `AGENTS.md`, and (routed, read-only) `~/.claude/CLAUDE.md`.
- **Observable**: content is loaded in full at launch **and** into every non-fork subagent. Content
  that only matters to one part of the tree belongs in a nested `CLAUDE.md` below cwd or a
  `paths:`-scoped rule — memory.md: "If an entry is a multi-step procedure or only matters for one
  part of the codebase, move it to a skill or a path-scoped rule instead."
- **Must NOT flag**: content that genuinely must reach every subagent. Explore and Plan skip
  CLAUDE.md entirely and there is no per-agent override — sub-agents.md: "There is no frontmatter
  field or per-agent setting to change which agents skip them" — so a rule those agents must obey
  has to be restated in the delegation prompt, not moved out of CLAUDE.md.

## Targets in this repo

Population, by command:

```
ls plugins/*/skills/*/SKILL.md | wc -l                       # 181 skill entrypoints
ls -1 plugins | wc -l                                        # 60 plugins
find plugins -path '*/agents/*.md' | wc -l                   # 7 agent definitions (546 lines total)
wc -l CLAUDE.md AGENTS.md                                    # 63 / 28
ls .claude/                                                  # settings.json, source-control.md — no rules/ dir
find . -name CLAUDE.md                                       # ./CLAUDE.md only — no nested CLAUDE.md
grep -nE '(^|[^`])@[A-Za-z0-9_./~-]+' CLAUDE.md              # no matches — no @ imports
grep -l '^paths:' plugins/*/skills/*/SKILL.md | wc -l        # 0 — path-scoped skill activation unused
```

Six `SKILL.md` files exist below the entrypoint depth and are **not** loaded skills — vendored
upstream copies under `vendor/`, the largest being
`plugins/playbooks/skills/boris/vendor/SKILL.md:1` at 1,717 lines. Any size audit must exclude them
or it will report a phantom 500-line violation.

### Tier 1 — always loaded, cannot be deferred (C5.4, C5.5)

**This is the all-plugins-enabled ceiling, not what any one session pays.** A session pays only for
the plugins it has enabled. The ceiling is nonetheless the number a marketplace author owns, because
it is what a consumer who enables everything gets.

- **130 listing-eligible skills → 80,188 chars.** At a 4-chars/token proxy that is ≈20,047 tokens —
  **but the budget's denomination is not stated on either official page.** The env-var alternative
  is named `SLASH_COMMAND_TOOL_CHAR_BUDGET` and is described as "a fixed character count", and the
  sibling `skillListingMaxDescChars` is char-denominated, so the budget may itself be characters. If
  it is tokens, this repo sits at roughly the 0.1-fraction line on a 200K-window model; if it is
  characters, it is several times over. Do not quote the token figure without the proxy label.
- **51 skills set `disable-model-invocation: true`**, carrying 25,149 chars of description that
  context-window.md says are not paid: "Skills with `disable-model-invocation: true` are not in this
  list. They stay completely out of context until you invoke them with `/name`." Reconciling this
  against skills.md's "The listing always contains every skill name": the consistent reading is that
  skills.md describes the model-invocable listing, whose *names* are always present, while
  context-window.md is specific that the `disable-model-invocation` set is absent from it. The two
  can be reconciled as "name retained, description not paid" or "entry absent entirely"; the saving
  holds either way, since 51 retained names are ≈1.3K chars against 25,149 of description. Almost
  all 51 are `<plugin>:setup` skills — the repo has already applied C5.5 to that class correctly.
- Mean listing-eligible description: **617 chars**. Median across all 181: **556**. Range 237–1,163.
- **All 181 exceed 200 chars; 109 exceed 500 chars.**
- Zero skills lack a `description` field.

**Per-plugin subtotals are the actionable unit**, because Conflict 4 establishes that `skillOverrides`
cannot reach plugin skills and `/plugin` toggles whole plugins:

| Chars | Skills | Plugin |
|---|---|---|
| 9,479 | 15 | `re-anchor` |
| 7,175 | 11 | `session-flow` |
| 6,542 | 10 | `planning` |
| 5,563 | 7 | `work-items` |
| 5,334 | 9 | `songwriting` |
| 4,079 | 6 | `docs-hygiene` |
| 3,259 | 6 | `source-control` |
| 2,219 | 4 | `claude-config` |
| 2,070 | 3 | `knowledge` |
| 2,022 | 2 | `adhd` |

**The top 10 plugins are 47,742 chars — 60% of the whole ceiling.** Tier 1 remediation is a
ten-plugin problem, not a 130-skill one.

Largest individual always-loaded entries:
`plugins/docs-hygiene/skills/audit-derivability/SKILL.md:1` (1,163),
`plugins/session-flow/skills/running-retro/SKILL.md:1` (1,118),
`plugins/session-flow/skills/reconcile/SKILL.md:1` (1,074),
`plugins/adhd/skills/clarify/SKILL.md:1` (1,060),
`plugins/architecture/skills/improve/SKILL.md:1` (1,059),
`plugins/re-anchor/skills/script-the-deterministic-work/SKILL.md:1` (1,056).

**Corroborating observation, not a measurement.** In this session's own in-context skill listing, a
large majority of this repo's skills appear name-only while roughly three dozen retain full
descriptions — consistent with skills.md's documented overflow behavior ("drops descriptions
starting with the skills you invoke least"). I am deliberately not reporting a count: I am running
as a **subagent**, whose startup composition differs from a main thread (sub-agents.md's "What loads
at startup" list does not even enumerate a skill listing), and the installed set is the user's
marketplace copy, not this worktree. The clean way to measure this is `claude --debug` and grepping
for the listing-overflow warning skills.md says gets written to the debug log. **I did not run it**
— a nested CLI invocation would start a real billed session against the user's installed
configuration rather than this worktree, which is both side-effectful and measuring the wrong tree.
Recommend the operator run `/doctor` in a main-thread session on this repo, which skills.md says
gives "an estimate of the listing's context cost and its biggest contributors."

### Tier 2 — loaded on invocation, persists all session (C5.2, C5.6)

- **0 of 181 bodies exceed the 500-line tip.** Largest:
  `plugins/source-control/skills/babysit-prs/SKILL.md:1` at 499 lines. Distribution: ≤100 lines 63,
  101–200 91, 201–300 20, 301–500 7.
- **But 13 of 181 bodies exceed the ~5,000-token compaction re-attach cap** at the nominal
  4-chars/token proxy. The count is proxy-sensitive: **20** at a conservative 3.5, **11** at a
  generous 4.5. All figures are post-frontmatter body bytes. This is the finding the line-count
  check misses entirely — the repo passes the documented tip and fails the documented truncation
  limit:

  | Body bytes | ≈tokens | Lines | Path |
  |---|---|---|---|
  | 41,723 | 10,431 | 338 | `plugins/planning/skills/plan/SKILL.md:1` |
  | 39,403 | 9,851 | 493 | `plugins/source-control/skills/babysit-prs/SKILL.md:1` |
  | 36,072 | 9,018 | 403 | `plugins/knowledge/skills/youtube-digest/SKILL.md:1` |
  | 33,947 | 8,487 | 258 | `plugins/planning/skills/interview/SKILL.md:1` |
  | 32,865 | 8,216 | 437 | `plugins/autonomy/skills/setup/SKILL.md:1` |
  | 30,231 | 7,558 | 207 | `plugins/work-items/skills/work/SKILL.md:1` |
  | 29,593 | 7,398 | 261 | `plugins/source-control/skills/commit/SKILL.md:1` |
  | 28,751 | 7,188 | 273 | `plugins/source-control/skills/pull-request/SKILL.md:1` |
  | 24,502 | 6,126 | 355 | `plugins/source-control/skills/babysit-loop/SKILL.md:1` |
  | 24,357 | 6,089 | 211 | `plugins/implementation/skills/implement/SKILL.md:1` |
  | 23,162 | 5,791 | 331 | `plugins/disk-hygiene/skills/clean/SKILL.md:1` |
  | 21,995 | 5,499 | 296 | `plugins/work-items/skills/setup/SKILL.md:1` |
  | 20,088 | 5,022 | 164 | `plugins/work-items/skills/triage/SKILL.md:1` |

  Seven more sit in the 17,500–20,000-byte band — in scope at 3.5 chars/token, out at 4.0, and
  therefore unresolved until a real tokenizer is used: `plugins/code-tidying/skills/tidy/SKILL.md:1`
  (19,450), `plugins/education/skills/teach/SKILL.md:1` (19,200),
  `plugins/planning/skills/prd/SKILL.md:1` (18,306),
  `plugins/implementation/skills/implement-dispatch/SKILL.md:1` (18,304),
  `plugins/discovery/skills/research/SKILL.md:1` (17,967),
  `plugins/planning/skills/devils-advocate/SKILL.md:1` (17,941),
  `plugins/work-items/skills/work-loop/SKILL.md:1` (17,869).

  Note the shape: several of the over-cap skills have *small* support trees relative to body
  (`plugins/planning/skills/plan/SKILL.md` — 41,723-byte body vs 40,855 bytes of support;
  `plugins/work-items/skills/setup/SKILL.md` — 21,995 vs 4,485). Those are the genuine "put it all
  upfront" cases.

- **The 25,000-token shared re-attach budget binds sooner than the per-skill cap.** 25,000 / 5,000
  means the shared budget holds exactly **five** at-cap skills. This repo has **13 bodies at or
  above the cap**, so a chain of six evicts its own earliest member — skills.md: "older skills can
  be dropped entirely after compaction if you have invoked many in one session." This repo's
  composition pattern (router skills, plan → implement → review chains) reaches six heavy
  invocations routinely.
- Total entrypoint body bytes across all 181: **1,754,312** (~439K tokens at the 4-char proxy, if
  every skill were invoked in one session).
- **65 of 181 skills contain `` !`cmd` `` injection** (C5.6). Heaviest by count:
  `plugins/claude-memory/skills/audit/SKILL.md:1` (7),
  `plugins/claude-ops/skills/observability/SKILL.md:1` (6),
  `plugins/review/skills/fanout/SKILL.md:1`, `plugins/session-flow/skills/retro/SKILL.md:1`,
  `plugins/source-control/skills/commit/SKILL.md:1` (5 each). These need per-injection output-bound
  review, not a count-based flag.

### Tier 3 — the on-demand tree (largely healthy)

- `context/` subtrees: **53 directories, 186 `.md` files, 1,142,240 bytes.**
- `reference/` + `references/` subtrees: **30 directories, 124 `.md` files, 1,171,043 bytes.**
- Total support `.md` across all skills: **2,731,910 bytes** — roughly 1.4x the always-invoked body
  tier, deferred.
- Best-shaped examples (support:body ratio): `tdd:principles` 28.3x, `playbooks:boris` 18.2x,
  `playwright:playwright` 14.6x, `songwriting:suno` 12.5x, `playbooks:fable-5` 10.6x. **These are
  the target state, not findings.**
- **Transitive reachability: 11 unreachable support `.md` of 395 candidates, across 6 of 181 skills**
  (BFS from the SKILL.md body through named `.md` files, excluding `evals/`, `scripts/`, `tests/` —
  method above):
  - `plugins/ai-briefing/skills/generate/context/execution-flow.md`
  - `plugins/implementation/skills/implement/context/gotchas.md`
  - `plugins/machine-health/skills/audit/` — `README.md`,
    `references/shared/correlation-rules.md`, `references/shared/testing.md`,
    `references/windows/elevation-matrix.md`
  - `plugins/repo-fleet-hygiene/skills/audit/reference/official-sources.md`,
    `.../reference/security-review.md`
  - `plugins/songwriting/skills/suno/templates/classical.md`, `.../templates/lofi.md`
  - `plugins/source-control/skills/commit/.claude/source-control.local.md` — **false positive**, a
    config file rather than reference material; exclude from any remediation.

  Real count is therefore ~10 files across 5 skills — a very good result for a 395-file tree, and
  strong evidence the repo already builds the tree the article prescribes. `songwriting:suno`'s two
  entries are suspicious given its other ten genre templates *are* reachable; verify by reading
  before filing.

### Tier 0 — CLAUDE.md (conformant)

`CLAUDE.md:1` is **63 lines**, well under memory.md's "target under 200 lines". No `@` imports, no
`.claude/rules/`, no nested `CLAUDE.md`. The article's loudest CLAUDE.md warning does not land here.
`AGENTS.md:1` (28 lines) is a separate file; memory.md states "Claude Code reads `CLAUDE.md`, not
`AGENTS.md`", so it costs nothing unless imported — and it is not.

**Routed recommendation, user-global scope (read-only to me, not edited).**
`~/.claude/CLAUDE.md` already implements exactly the pattern claim 8 prescribes: a "Reference docs
(read on demand)" section that points at five `~/.claude/docs/*.md` files by path with the explicit
note "These files are not loaded automatically. Use the Read tool when the task touches that
domain." That is a correct deferring shape — path pointers Claude reads on demand, **not** `@`
imports, which would have loaded all five at launch. Flag it as an exemplar for this repo's own
remediations, not as a defect. Its one risk is C5.7: at its current size it is re-paid into every
non-fork subagent this repo's skills spawn, and the repo's skills spawn many.

## Conflicts and ambiguity

1. **The official docs give two different skill-listing budgets, and I am not adjudicating.**
   - <https://code.claude.com/docs/en/skills.md>: "The budget scales at **1%** of the model's
     context window" and each entry's "combined `description` and `when_to_use` text is truncated at
     **1,536 characters**".
   - <https://code.claude.com/docs/en/settings.md>: `skillListingBudgetFraction` **"Default: `0.1`"**
     (10%), and `skillListingMaxDescChars` **"Default: `200`"**, range 50–500.

   These are order-of-magnitude apart on both numbers. Evidence one page lags: settings.md links to
   `skills#control-skill-listing-verbosity` and `skills#override-skill-metadata`, and **neither
   anchor exists** in the skills.md I fetched (its sections are "Skill descriptions are cut short"
   and "Override skill visibility from settings").

   A third ambiguity compounds it: **neither page states the budget's denomination.** The fraction
   is "of the context window" (tokens), but the env-var alternative is
   `SLASH_COMMAND_TOOL_CHAR_BUDGET`, "a fixed character count", and `skillListingMaxDescChars` is
   char-denominated. 80,188 chars is either ≈20,047 tokens (at a 4-char proxy) or 80,188 chars, and
   those land very differently against a 200K-window model.

   **Every criterion here is robust across all of it**: 80,188 chars / a 617-char mean blow past the
   smallest candidate cap (200 chars/entry) by 3x, and land at or beyond the budget under every
   combination of the two fractions and two denominations except the single most generous one
   (0.1 × tokens × a 1M-context model). What the ambiguity *does* change is the remediation target —
   hence the operator question below.

2. **The article says "the same can be applied to your own CLAUDE.md" — the most natural reading is
   wrong.** A reader who takes claim 6 at face value splits CLAUDE.md into `@`-imported files and
   measures zero improvement, because memory.md says twice, explicitly, that imports load at launch.
   This is the single most likely way to misapply S5. Any remediation this repo emits must be
   audited against C5.1.

3. **Splitting a long skill into several skills is a net context *loss*, not a win.** Article line
   107 says "For long skills… divide it into many files and split them out" — correct if "files"
   means support files, wrong if it means additional skills, because each new skill adds a
   permanently-loaded listing entry. The article's wording does not disambiguate.

4. **The repo's own `docs/MIGRATION-PLAYBOOK.md:78` states the constraint that makes Tier 1 hard,
   and it checks out.** It says "`skillOverrides` setting explicitly *excludes* plugin skills (those
   are managed through `/plugin`)". Confirmed verbatim at skills.md: "Plugin skills are not affected
   by `skillOverrides`." Consequence: for a plugin marketplace, skills.md's recommended budget
   remedy — "set low-priority entries to `"name-only"` in `skillOverrides`" — **is unavailable**.
   The author-side levers reduce to (a) trim description text, (b) `disable-model-invocation: true`,
   (c) ship fewer skills. A consumer can only disable whole plugins via `/plugin`. Any Tier 1
   remediation that reaches for `skillOverrides` is dead on arrival here.

5. **The 500-line tip and the 5,000-token re-attach cap are different limits, and this repo's clean
   result on the first is misleading.** 0/181 over 500 lines reads as full conformance; 14/181 over
   the truncation cap says otherwise. A remediation checklist that encodes only the line count will
   certify skills whose tails the harness silently drops.

6. **High support:body ratio must not be treated as a smell.** `tdd:principles` at 28.3x is the
   correct shape. Stated explicitly because a naive "large skill directory" heuristic inverts the
   section's entire thesis.

7. **`context: fork` interaction with the persistence and re-attach profile is unresolved.**
   skills.md says a forked skill's "skill content becomes the prompt that drives the subagent" in a
   separate context window — which plausibly means the 5,000-token re-attach cap does not apply the
   same way, since the body is a prompt rather than an in-conversation skill message. **No page I
   fetched states this either way.** Only one repo skill sets `context: fork`
   (`grep -l '^context:[[:space:]]*fork' plugins/*/skills/*/SKILL.md` → 1), so the blast radius is
   near zero today, but C5.2 should not be asserted over forked skills without verifying it.

8. **This section's mechanisms are version-gated, and the repo has no stated floor.** The docs carry
   min-version markers throughout (`skillOverrides` `"off"` behavior v2.1.199, re-invocation
   de-duplication v2.1.202, skill-listing row accounting v2.1.196, path-scoped rule fixes v2.1.207 /
   v2.1.211 / v2.1.217). A criterion asserting deferral behavior implicitly asserts a minimum
   Claude Code version. I did not find a declared minimum in this repo's root docs.

9. **Claim 1 is unfalsifiable and should not become a criterion.** The system prompt is not
   published. Nothing in this repo can be audited against "what the system prompt used to contain."
   It motivates the section; it does not generate a rule.

## Open questions for the operator

1. **How do we set a Tier 1 target given the budget is unresolved on both magnitude and unit?**
   RECOMMENDED: **do not adopt any budget figure as an authoring target.** The budget governs how
   much overflow-dropping the harness does; it is not a number an author can aim at. Targeting the
   pessimistic reading (1% of a 200K window ≈ 2,000 tokens across 130 skills ≈ 61 chars each) would
   force exactly the vagueness C5.4's must-not-flag clause forbids. Set the target on the
   *actionable unit* instead — a per-plugin listing budget, prioritized by the ten plugins that
   carry 60% of the ceiling, with the reduction taken from redundancy and trailing "Not for X"
   clauses rather than from trigger keywords.
2. **Should this be settled by running `/doctor` on a main-thread session in this repo before any
   Tier 1 remediation is scoped?** RECOMMENDED: yes — skills.md says `/doctor` reports both the
   listing's context cost and its biggest contributors, which converts question 1 from a doc
   conflict into a measurement and resolves the denomination question empirically. It needs a main
   thread; I cannot run it from here.
3. **Is a 617-char mean description a defect or a deliberate discovery investment?** RECOMMENDED:
   deliberate but over-budget — reduce by front-loading trigger keywords and cutting the trailing
   "Not for X" clauses that several descriptions carry, rather than by shortening uniformly. Losing
   trigger keywords costs discovery, which is the thing the listing exists to buy.
4. **Do we adopt the ~5,000-token body cap (C5.2) as a hard gate in `scripts/`, alongside the
   existing skill checks?** RECOMMENDED: yes, as a warning first — the byte→token proxy needs a
   real tokenizer before it becomes a blocking gate.
5. **Should `plugins/*/skills/*/SKILL.md` frontmatter `paths:` (currently 0 uses) be adopted for
   ecosystem-specific skills?** RECOMMENDED: evaluate but do not mandate — it defers *auto-*
   invocation only, and most skills here are workflow-triggered rather than file-triggered, so the
   fit is narrow.
6. **What minimum Claude Code version does this repo declare?** RECOMMENDED: declare one explicitly
   in `docs/PLUGIN-PHILOSOPHY.md` or the root README; several deferral behaviors this section relies
   on are gated at v2.1.196–v2.1.218.
7. **Do the ~10 unreachable support files get wired into their SKILL.md, or deleted?**
   RECOMMENDED: read each first — the `songwriting:suno` pair especially, where the sibling
   templates *are* reachable, suggests a naming mismatch rather than dead content.

## Fence events

None. I did not read, list, grep, or reference any path under
`docs/topics/context-engineering-claude-5/**`, `docs/topics/fable-field-guide-audit/**`,
`.work/fable-field-guide-audit/**`, any other worktree, or any other agent's file under `sections/`.
My `find docs -type f -name '*.md' | head -40` listing of `docs/` truncated before reaching
`docs/topics/context-engineering-claude-5/` alphabetically; the visible tail was
`docs/topics/ai-adoption-ladder/design/*`, and I did not page further or open anything under
`docs/topics/`. The only `docs/topics/` path that appeared anywhere in my output was
`docs/topics/plugin-fleet-sync-skill/PLAN.md`, surfaced as a filename by a `grep -rln 'progressive
disclosure'` across `docs/`; I did not open it.
