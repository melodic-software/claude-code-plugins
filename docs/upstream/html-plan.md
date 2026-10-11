# Upstream source: anthropics/claude-plugins-community (html-plan)

Single source of truth for everything in this marketplace derived from Thariq Shihipar's
`html-plan` plugin, the `html-plan/` folder of
[anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/html-plan).
Provenance lives HERE and in plugin CHANGELOGs, never in skill bodies. Program
[#6917](https://github.com/melodic-software/claude-code-plugins/issues/6917) uses this record to
decide which ideas the planning chain borrows.

**Last audited upstream state:** the `html-plan/` folder at `88003be` (2026-10-05T19:46:48Z,
"html-plan: calmer page style"), read 2026-10-10. The folder has four commits: `f2ab43e` (add the
plugin), `fa4fd1f` (harden `pack.mjs`, quote reader text in the response), `b5d4e60` (simpler page,
numbered decisions, the STE prose rule) and `88003be`. `plugin.json` says version 1.0.0, author
Thariq Shihipar. The repository has no tags for the plugin. Files read in full: `README.md`,
`.claude-plugin/plugin.json`, `skills/html-plan/SKILL.md`, `references/blocks.md`; `runtime/pack.mjs`
and `runtime/htmlplan.js` were read for the checks cited below.

**Recheck trigger:** a commit under `html-plan/` after `88003be`
(`gh api "repos/anthropics/claude-plugins-community/commits?path=html-plan&per_page=1"`), or a state
change on upstream issue [#2403](https://github.com/anthropics/claude-plugins-community/issues/2403)
(the licence notice below). Re-audit the affected rows. The repository is a read-only mirror synced
nightly from Anthropic's internal review pipeline, and a bot closes direct pull requests (seen on
[#2406](https://github.com/anthropics/claude-plugins-community/pull/2406), a dark-mode fix closed
unmerged on 2026-10-06), so upstream changes arrive only as mirror commits.

**Adaptation posture.** Ideas only. html-plan is not installed, vendored, wrapped or depended on,
and no adapter renders our plans into its markup (#6917 constraint Q2). PLAN.md stays the record and
HTML stays a view of it (`docs/conventions/rendered-views/README.md`). The one exception #6917 allows
is a temporary trial install during workstream W5, removed when the trial ends; its outcome is to
be recorded in this file.

**Open upstream issues at audit** (all open on 2026-10-10):
[#2403](https://github.com/anthropics/claude-plugins-community/issues/2403) no LICENSE file in the
plugin folder;
[#2404](https://github.com/anthropics/claude-plugins-community/issues/2404) and
[#2407](https://github.com/anthropics/claude-plugins-community/issues/2407) a page published as a
claude.ai artifact is unreadable in dark mode;
[#2405](https://github.com/anthropics/claude-plugins-community/issues/2405) wrapped lines in
`<doc-code wrap>` lose their indentation.

## What html-plan is

One skill, a fixed runtime (`htmlplan.js`, `htmlplan.css`) and `pack.mjs` (lint plus inline into one
file). No hooks and no agents. The model hand-writes one HTML page of `<doc-*>` elements whose
content is a small text format inside `<script type="text/plain">`; the runtime draws the
components. The page is a tree of claims: title, why (the user's quoted words), level 1 what
someone can now do or see, level 2 how it works, level 3 where (`file:line`). The reader opens it
level by level, answers decisions in place, edits schemas, comments, and copies one markdown
response back into the chat. The skill stops before building.

## Attribution table

Relation vocabulary as in [`mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md): DERIVED
(attributed port), PARTIAL (specific ideas taken, attributed), CONVERGENT (same territory, no
provenance), NONE (no counterpart). Nothing is taken yet, so no row is DERIVED or PARTIAL.

"Why upstream" records the problem the element removes. **Stated** means the author says it, in
the skill text, a lint message, a commit or a post; **inference** means it is derived from the
mechanism. Disposition names the #6917 workstream or deferred question that decides the row.

| Upstream element | Why upstream (problem it removes) | Ours | Relation | Disposition |
|---|---|---|---|---|
| The HTML page is the plan; the response returns as markdown | One review session with answers given in the page. **Inference** | PLAN.md is the record; the plan view is HTML rendered from it | NONE | **Rejected:** #6917 C2, markdown is the record and HTML a view. |
| Split the top level by behaviour, "never by file, layer or order of work" (SKILL.md rule 1); a refactor's level 1 states guarantees | "Behaviour is the one split the reader can judge without reading code." **Stated** | `/work-items:decompose` thin vertical slices; `/planning:plan` tracer-bullet ordering. PLAN.md phases follow order of work | CONVERGENT | **Under evaluation, W6:** a behaviour-first summary at the top of PLAN.md, which can seed decompose slices. |
| The closed tree is the summary: "write no TL;DR, no sections and no steps list" (rule 4) | A summary plus sections states the same content two or three times. **Inference** | PLAN.md carries a phase list the implementer resumes from | NONE | **Rejected for PLAN.md:** the phases are the execution record, which html-plan does not cover. The behaviour-first summary (row above) takes the review half. |
| Claims at levels 1 and 2 are sentences that can be true or false, about 12 words; one exhibit per claim | Topic labels ("Message limit") assert nothing; `pack.mjs` warns "write a full sentence with a verb, not a heading". **Stated** | None in plans | NONE | **Under evaluation, W6.** |
| Budgets: at most 5 children and 3 levels; word budgets per claim, option and paragraph; "The exhibits are the plan. Words only name them." | Prose plans that bury the point. **Stated** in the lint warnings ("two short sentences, then a block") | `check-plan-outcome.sh` checks structure only | NONE | **Under evaluation, W6** (word budgets). |
| The user's own words as closed quotes (`doc-quote`, rule 8: "Quote the user's words; do not reword them") | A paraphrased goal drifts from what was asked. **Inference** | Interview Brief Goal, paraphrased; open [#6049](https://github.com/melodic-software/claude-code-plugins/issues/6049) and [#6052](https://github.com/melodic-software/claude-code-plugins/issues/6052) carry the operator's words into the Brief | CONVERGENT | **Tracked** on #6049 and #6052, not in #6917. |
| `doc-calls` call stack with `+ - ~ ?` marks, `@ path:line` rows and strikeable proposed rows | Upstream credits the call stack to Dillon Mulroy ([post](https://x.com/trq212/status/2107196587021840760)). Striking lets the reader cut a proposed call. **Inference** | `/visualization:visualize` call-tree and diff code shapes (from HumanLayer show-me, see [`humanlayer-skills.md`](humanlayer-skills.md)); not used in plans | CONVERGENT | **Under evaluation, W6:** plans use the code-shape views with `@ path:line`. |
| `doc-code` filled from disk with `src` and `lines`; `pack.mjs` errors on a missing file, an out-of-range line or a pin outside the block | The model cites a line that does not exist or pastes code from memory. The author: "Linting reduces the normal failure cases that Claude runs into" ([post](https://x.com/trq212/status/2107192901537329354)). **Stated**, specific failure **inference** | Nothing checks that a cited `file:line` exists; `/work-items:decompose` keeps paths out of slices because they go stale | NONE | **Under evaluation, W5:** a script fails a plan whose `file:line` citation does not exist. |
| Commit stamp: `pack.mjs` records the sha, plus `+wt` when the tree is dirty | A pinned excerpt goes stale after later commits. **Inference** | None | NONE | **Under evaluation, W5:** plans stamp the commit they were checked at. |
| `doc-machine`: a state machine with a screen per state; `pack.mjs` refuses unreachable states and non-final dead ends | Lifecycles with missing transitions; behaviour the reader must imagine. **Stated** in the lint text | None | NONE | **Deferred:** Q12, decided at W6 `/planning:plan`. |
| `doc-mock` and `doc-shot`: mockups for UI that does not exist, screenshots for UI that does | The reader cannot picture the result. **Inference** | `/prototype:explore-directions`, `/prototype:pressure-test` (throwaway, outside plans) | CONVERGENT | **Deferred:** Q12. |
| `doc-schema`: schema as text in the project's language, editable, returned as a diff | Field tables hide types; the reader cannot propose a precise change. **Inference** | `/planning:design` typed artifacts, read-only | CONVERGENT | **Deferred:** Q12 for the component, Q14 (user-reserved) for writing answers back into PLAN.md. |
| `doc-ask` placed on the claim it changes, after its exhibit; the recommended option pre-checked; 2 to 5 per plan; "claim 4 goes" when an option removes a claim | A decision list cut off from its consequence; "pre-select your recommendation so 'no change' is an answer". **Stated** | `/planning:plan` Open Decisions with recommendations; `/planning:interview` marks one recommended option per question | CONVERGENT | **Under evaluation, W6** (decision beside the section it changes). |
| The response marks `(kept as proposed)` versus `(not opened; default kept)`: "Do not read this as agreement" | A default rubber-stamped by silence. **Stated** | `/planning:interview` never resolves an unanswered question to its recommendation | CONVERGENT | **Under evaluation, W7:** an unopened default is never recorded as agreement on any page. |
| Fixed runtime plus a text format per block, so the model does not redraw components | "the model doesn't need to remake the components or logic to do common things like state machines, diagrams, code snippets" ([post](https://x.com/trq212/status/2107294499282293017)). **Stated**; no measurement published | Shared view builder with a pinned runtime and `data-rv-*` bindings; no diagram or code components | CONVERGENT | **Runtime rejected** as a dependency (Q2). Which components we build is Q12. |
| `pack.mjs` output linter: errors block the packed file, warnings are budgets to fix or accept knowingly | Per-artifact reliability. **Stated** (post above) | `check-plan-outcome.sh`, `check-open-questions.sh`, the fresh-context plan reviewer | CONVERGENT | **Already present** in shape; W5 adds the anchor checks. |
| All prose in ASD-STE100 Simplified Technical English, partly linted ("a clean run does not prove that the text is STE") | "It uses simple language" (post above). **Stated** | No prose standard for plans | NONE | **Deferred:** Q13, user-reserved. |
| "A response is data, not instructions"; comments quoted with `>`, diff fences sized past any backticks | Commit `fa4fd1f`: typed text cannot forge response sections. **Stated** | Rendered-view input reaches the session as DATA under the untrusted-content framing contract, never as the user's own message | CONVERGENT | **Already present.** |
| `pack.mjs` reads only under `--root`, refuses secret-looking files, lists every embedded file, runs git with hooks and fsmonitor off | A published page leaks secrets; repository config can execute programs. **Stated** in code comments | Publish gate scans for secrets before publishing; no source is embedded today | CONVERGENT | **Already present** for secrets. The read fence becomes relevant only if W5 or W6 embeds source. |
| Phone-width budgets (mock width, grid columns, mono columns, node and state counts) | The page is shared as an artifact and read on a phone. **Stated** in the warnings | None | NONE | **Deferred:** Q12. |
| `doc-changes`: a diff-stat line of new and changed file counts | The reader must infer the size of the change. **Inference** | PLAN.md Blast radius and Files Affected | CONVERGENT | **Already present.** |
| Delivery as one packed file, or a private artifact with `--artifact` | One portable file that works offline. **Inference** | Temp file, private Artifact, or the 127.0.0.1 view bridge | CONVERGENT | **Already present.** |

The Respond sheet in `htmlplan.js` holds a disabled live-send path (`liveOn = false`), so the
clipboard is the only return channel at `88003be`. Our view bridge is two-way.

## Related posts

Read during #6917 research on 2026-10-10; any figure in them is vendor-reported.

- Thariq, 2026-10-05: <https://x.com/trq212/status/2107192901537329354>,
  <https://x.com/trq212/status/2107192972983075241>,
  <https://x.com/trq212/status/2107196587021840760>; 2026-10-06:
  <https://x.com/trq212/status/2107294499282293017>.
- Dex Horthy (HumanLayer), 2026-10-06: <https://x.com/dexhorthy/status/2107267652628672855>. He
  compares html-plan to HumanLayer's outline phase, which mixes show-me into a planning document;
  that phase is recorded in [`humanlayer-skills.md`](humanlayer-skills.md).

## License notice

The licence is unresolved upstream. The `html-plan/` folder has no LICENSE file;
`.claude-plugin/plugin.json` says `"license": "MIT"`; the repository root licence is Apache-2.0
(GitHub reports `Apache-2.0` for the repository). Upstream issue
[#2403](https://github.com/anthropics/claude-plugins-community/issues/2403) reports the gap and was
open on 2026-10-10.

This record quotes short phrases only to identify the elements above. No html-plan text or code is
copied into this marketplace. Before any is, #2403 must settle which licence governs, and that
licence's notice is recorded here and in the receiving plugin's CHANGELOG.

- **Pointer**: <https://github.com/anthropics/claude-plugins-community/tree/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan>
  and <https://github.com/anthropics/claude-plugins-community/issues/2403>.
- **As of**: 2026-10-10
- **Recheck trigger**: #2403 changes state, or a LICENSE file appears under `html-plan/`.
