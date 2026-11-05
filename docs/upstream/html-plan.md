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
(the license notice below). Re-audit the affected rows. The repository is a read-only mirror synced
nightly from Anthropic's internal review pipeline, and a bot closes direct pull requests (seen on
[#2406](https://github.com/anthropics/claude-plugins-community/pull/2406), a dark-mode fix closed
unmerged on 2026-10-06), so upstream changes arrive only as mirror commits.

**Adaptation posture.** Ideas only. html-plan is not installed, vendored, wrapped or depended on,
and no adapter renders our plans into its markup (#6917 constraint Q2). PLAN.md stays the record and
HTML stays a view of it (`docs/contracts/rendered-views/README.md`). The one exception #6917 allows
is a temporary trial install during workstream W5, removed when the trial ends.

**Trial outcome (2026-11-02, [#10067](https://github.com/melodic-software/claude-code-plugins/issues/10067)).**
html-plan at `88003be` planned #6927 beside `/planning:plan`; the install was removed after. The
owner's review of the page changed D1 (the Brief stays first) and D3 (code detail moves to the
design; plans anchor by path plus symbol), redefined D2 (slice seeding), and added three asks: an
example that redraws per option, choices the session reads live, and a system-default theme
toggle. Stock html-plan rendered a light page background under dark claim bars in dark mode;
upstream's fix [#2406](https://github.com/anthropics/claude-plugins-community/pull/2406) was closed
unmerged. Full record:
[#6924 comment](https://github.com/melodic-software/claude-code-plugins/issues/6924#issuecomment-6589117909).

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
components. The page is a claim tree: title, why (the user's quoted words), level 1 what
someone can now do or see, level 2 how it works, level 3 where (`file:line`). The reader opens it
level by level, answers decisions in place, edits schemas, comments, and copies one markdown
response back into the chat. The skill stops before building.

## Attribution table

Relation vocabulary as in the [`mattpocock-skills.md` Map](mattpocock-skills.md#map): DERIVED
(attributed port), PARTIAL (specific ideas taken, attributed), CONVERGENT (same territory, no
provenance), NONE (no counterpart). Nothing is taken yet, so no row is DERIVED or PARTIAL.

"Why upstream" records the problem the element removes. **Stated** means the author says it, in
the skill text, a lint message, a commit or a post; **inference** means it is derived from the
mechanism. Disposition names the #6917 workstream or deferred question that decides the row.

| Upstream element | Why upstream (problem it removes) | Ours | Relation | Disposition |
|---|---|---|---|---|
| The HTML page is the plan; the response returns as markdown | One review session with answers given in the page. **Inference** | PLAN.md is the record; the plan view is HTML rendered from it | NONE | **Rejected:** #6917 C2, markdown is the record and HTML a view. |
| Top-level split by behavior, with files, layers and work sequence ruled out as split keys (SKILL.md rule 1); a refactor's level 1 states guarantees | A split by file or layer takes code knowledge to assess, and a behavior split does not. **Stated** ([source](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/SKILL.md)) | `/work-items:decompose` thin vertical slices; `/planning:plan` tracer-bullet ordering. PLAN.md phases follow order of work | CONVERGENT | **Under evaluation, W6:** a behavior-first summary at the top of PLAN.md, which can seed decompose slices. |
| The closed tree stands in for a summary, so the page carries no TL;DR, section headings or step list (rule 4) | A summary plus sections states the same content two or three times. **Inference** | PLAN.md carries a phase list the implementer resumes from | NONE | **Rejected for PLAN.md:** the phases are the execution record, which html-plan does not cover. The behavior-first summary (row above) takes the review half. |
| Each claim on the first two levels is a sentence of about 12 words that is either true or false; one exhibit per claim | Topic labels, a bare noun phrase such as a feature name, assert nothing; `pack.mjs` warns when a claim reads as a heading instead of a sentence. **Stated** ([source](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs)) | None in plans | NONE | **Under evaluation, W6.** |
| Budgets: a cap of 5 children and of 3 levels; word budgets per claim, option and paragraph, which keep prose to labeling the exhibits that carry the plan | Prose plans that bury the point. **Stated** in the [lint warnings](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs), which cap the prose before an exhibit at two short sentences | `check-plan-outcome.sh` checks structure only | NONE | **Under evaluation, W6** (word budgets). |
| What the user said stays inside closed quotes and is never paraphrased (`doc-quote`, rule 8) | A paraphrased goal drifts from what was asked. **Inference** | Interview Brief Goal, paraphrased; open [#6049](https://github.com/melodic-software/claude-code-plugins/issues/6049) and [#6052](https://github.com/melodic-software/claude-code-plugins/issues/6052) carry the operator's words into the Brief | CONVERGENT | **Tracked** on #6049 and #6052, not in #6917. |
| `doc-calls` call stack with `+ - ~ ?` marks, `@ path:line` rows and strikeable proposed rows | Upstream credits the call stack to Dillon Mulroy ([post](https://x.com/trq212/status/2107196587021840760)). Striking lets the reader cut a proposed call. **Inference** | `/visualization:visualize` call-tree and diff code shapes (from HumanLayer show-me, see [`humanlayer-skills.md`](humanlayer-skills.md)); not used in plans | CONVERGENT | **Under evaluation, W6:** plans use the code-shape views with `@ path:line`. |
| `doc-code` filled from disk with `src` and `lines`; `pack.mjs` errors on a missing file, an out-of-range line or a pin outside the block | The model cites a line that does not exist or pastes code from memory. The author credits linting with cutting the common failures ([post](https://x.com/trq212/status/2107192901537329354)). **Stated**, specific failure **inference** | Nothing checks that a cited `file:line` exists; `/work-items:decompose` keeps paths out of slices because they go stale | NONE | **Under evaluation, W5:** a script fails a plan whose `file:line` citation does not exist. |
| Commit stamp: `pack.mjs` records the sha, plus `+wt` when the tree is dirty | A pinned excerpt goes stale after later commits. **Inference** | None | NONE | **Under evaluation, W5:** plans stamp the commit they were checked at. |
| `doc-machine`: a state machine with a screen per state; `pack.mjs` refuses unreachable states and non-final dead ends | Lifecycles with missing transitions: **Stated** in the [lint text](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/htmlplan.js#L213-L214) that [`pack.mjs` raises as errors](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs#L116). Behavior the reader must imagine: **Inference** | None | NONE | **Deferred:** Q12, decided at W6 `/planning:plan`. |
| `doc-mock` and `doc-shot`: mockups for UI that does not exist, screenshots for UI that does | The reader cannot picture the result. **Inference** | `/prototype:explore-directions`, `/prototype:pressure-test` (throwaway, outside plans) | CONVERGENT | **Deferred:** Q12. |
| `doc-schema`: a schema written as editable text in the project's language, returned as a diff | Field tables hide types; the reader cannot propose a precise change. **Inference** | `/planning:design` typed artifacts, read-only | CONVERGENT | **Deferred:** Q12 for the component, Q14 (user-reserved) for writing answers back into PLAN.md. |
| `doc-ask` attached to the claim whose outcome it alters, below that claim's exhibit; the recommended option pre-checked; between two and five per plan; an option that removes a claim names the claim it removes | A decision list cut off from its consequence, and a reader who has to act to accept the default. **Stated** ([SKILL.md](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/SKILL.md), [pack.mjs](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs)) | `/planning:plan` Open Decisions with recommendations; `/planning:interview` marks one recommended option per question | CONVERGENT | **Under evaluation, W6** (decision beside the section it changes). |
| The response marks `(kept as proposed)` versus `(not opened; default kept)`, so an unopened default never counts as consent | A default rubber-stamped by silence. **Stated** ([source](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/SKILL.md)) | `/planning:interview` never resolves an unanswered question to its recommendation | CONVERGENT | **Under evaluation, W7:** an unopened default is never recorded as agreement on any page. |
| Fixed runtime plus a text format per block, so the model does not redraw components | The model reuses the shipped components, such as state machines, diagrams and code blocks, instead of building them again for each plan ([post](https://x.com/trq212/status/2107294499282293017)). **Stated**; no measurement published | Shared view builder with a pinned runtime and `data-rv-*` bindings; no diagram or code components | CONVERGENT | **Runtime rejected** as a dependency (Q2). Which components we build is Q12. |
| `pack.mjs` output linter: errors block the packed file, warnings are budgets to fix or accept knowingly | Per-artifact reliability. **Stated** ([post](https://x.com/trq212/status/2107192901537329354)) | `check-plan-outcome.sh`, `check-open-questions.sh`, the fresh-context plan reviewer | CONVERGENT | **Already present** in shape; W5 adds the anchor checks. |
| Prose follows ASD-STE100 Simplified Technical English, partly linted, and the skill warns that passing the lint falls short of proving STE conformance | The author lists plain wording among the page's traits ([post](https://x.com/trq212/status/2107192901537329354)). **Stated** | No prose standard for plans | NONE | **Deferred:** Q13, user-reserved. |
| What the reader types into the response is framed as data, never as instructions: comments quoted with `>`, diff fences sized past any backticks | Commit [`fa4fd1f`](https://github.com/anthropics/claude-plugins-community/commit/fa4fd1f808d1c92e20a0748feb5a4a93708879c5): text a reader types could otherwise pass as a section of the response. **Stated** | Rendered-view input reaches the session as DATA under the untrusted-content framing contract, never as the user's own message | CONVERGENT | **Already present.** |
| `pack.mjs` reads only under `--root`, refuses secret-looking files, lists every embedded file, runs git with hooks and fsmonitor off | A published page leaks secrets; repository config can execute programs. **Stated** in [code comments](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs) | Publish gate scans for secrets before publishing; no source is embedded today | CONVERGENT | **Already present** for secrets. The read fence becomes relevant only if W5 or W6 embeds source. |
| Phone-width budgets (mock width, grid columns, mono columns, node and state counts) | The page is shared as an artifact and read on a phone. **Stated** in the [warnings](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/pack.mjs) | None | NONE | **Deferred:** Q12. |
| `doc-changes`: a diff-stat line of new and changed file counts | The reader must infer the size of the change. **Inference** | PLAN.md Blast radius and Files Affected | CONVERGENT | **Already present.** |
| Delivery as one packed file, or a private artifact with `--artifact` | One portable file that works offline. **Inference** | Temp file, private Artifact, or the 127.0.0.1 view bridge | CONVERGENT | **Already present.** |

The Respond sheet in `htmlplan.js` holds a disabled live-send path
([`liveOn = false`](https://github.com/anthropics/claude-plugins-community/blob/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan/skills/html-plan/runtime/htmlplan.js#L627)),
so the clipboard is the only return channel at `88003be`. Our view bridge is two-way.

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

The license is unresolved upstream. The `html-plan/` folder has no LICENSE file;
`.claude-plugin/plugin.json` says `"license": "MIT"`; the repository root license is Apache-2.0
(GitHub reports `Apache-2.0` for the repository). Upstream issue
[#2403](https://github.com/anthropics/claude-plugins-community/issues/2403) reports the gap and was
open on 2026-10-10.

This record quotes short phrases only to identify the elements above. No html-plan text or code is
copied into this marketplace. Before any is, #2403 must settle which license governs, and that
license's notice is recorded here and in the receiving plugin's CHANGELOG.

- **Pointer**: <https://github.com/anthropics/claude-plugins-community/tree/88003be1129c09381d27100b37a8fdc21b3214bf/html-plan>
  and <https://github.com/anthropics/claude-plugins-community/issues/2403>.
- **As of**: 2026-10-10
- **Recheck trigger**: #2403 changes state, or a LICENSE file appears under `html-plan/`.
