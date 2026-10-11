# Upstream source — humanlayer/skills (show-me, rpi)

Single source of truth for everything in this marketplace derived from
[humanlayer/skills](https://github.com/humanlayer/skills) — "Claude Code skills from HumanLayer",
MIT — and specifically its `plugins/show-me/skills/show-me/SKILL.md`. The `visualization` plugin's
code-shape sketch family is inspired by and adapted from that skill. The `rpi` plugin is evaluated
below for program [#6917](https://github.com/melodic-software/claude-code-plugins/issues/6917) and
nothing from it is adopted yet. Provenance lives HERE and in
plugin CHANGELOGs, never in skill bodies, where it is agent-facing noise. Content citations an agent
actually uses are not provenance records and stay in place.

**Last audited upstream state:** `main@3c26291` (upstream HEAD at audit, the merge of its PR #5,
2026-08-13T15:05:30Z). `plugins/show-me/skills/show-me/SKILL.md` last changed at `6ab9013` and is
byte-identical at that HEAD. "v1.0.1" is the plugin manifest version; the repository has no git
tags. Git history of this file records *when*; this line records only *what was audited*.
Trigger fired and re-audited 2026-10-04: `bba9d13` (2026-09-12) is the only later change to the
file. It adds `disable-model-invocation: true` to the frontmatter (plus a Codex
`allow_implicit_invocation: false` sidecar) and leaves the body untouched, so no row below changes.
Re-audited 2026-10-10 at `main@653b641` (2026-10-08T21:54:25Z, the merge of upstream PR #13, "Add a
portable RPI workflow for Claude Code and Codex"): `plugins/show-me/` has no commit after `bba9d13`.
The new `rpi` plugin carries a copy of the skill at `plugins/rpi/skills/rpi/references/show-me.md`,
identical to the pinned file except that its frontmatter lacks `disable-model-invocation: true`, so
no row below changes. Watch next: mattpocock/skills v1.3 `pr` re-hosts this skill's view menu (see
[`mattpocock-skills.md`](mattpocock-skills.md), `pr` row), so a later body change here should be
diffed against both `visualization`'s `code-shapes.md` and his `pr`.

**Recheck trigger:** a change to `plugins/show-me/skills/show-me/SKILL.md` against `bba9d13` (was
`6ab9013`), or to its copy `plugins/rpi/skills/rpi/references/show-me.md` against `653b641`:
re-audit the affected rows below. The `rpi` section has its own trigger. The upstream publishes no
release notes and no tags, so the trigger is a file change rather than a release, and the audit is a
diff against the pinned commit.

**Adaptation posture.** Every example block and guidance sentence that fit this marketplace's
`visualize` router was carried **verbatim**; three example blocks were **adapted** because as written
they describe implementing the upstream slash command itself; the surrounding prose was reauthored to
the router's structure and house style. The upstream skill is not shipped, wrapped, or depended on:
its trigger vocabulary ("show me", "sketch", "diagram") was already owned by `visualize`, the
marketplace's skill-split rule admits a second skill only on distinct triggers, and the listing
aggregate for the neighboring plugins is over budget. Bare `/show-me` is therefore not a command in
this marketplace; `/visualization:visualize` and the `'show me the shape of this'` trigger are.

## Attribution table

The pinned file has twenty elements: the frontmatter description, three intro sentences, eight form
bullets (four diff sub-fences inside the diff bullet), and four `### guidance` sentences. Every one
is accounted for.

| Upstream element | Ours | Relation | What was taken / rejected |
|---|---|---|---|
| Frontmatter description ("… concise diagrams, code-shape sketches, and focused HTML artifacts") | [`visualize` description](../../plugins/visualization/skills/visualize/SKILL.md) | Adapted | **Taken:** the phrase "code-shape sketches" as the family's name in the form list. **Rejected:** the rest; our description carries quoted triggers and the router's own contract. |
| Intro 1: "Help the user understand the current topic of conversation visually." | none | Not taken | **Rejected — comprehension framing:** `visualize` declares itself a form-and-medium router that is not comprehension-driven, and an earlier audit (the cursor-pstack `teach` row) already moved a comprehension rule out of it. The operative half ("the current topic of conversation") is Step 1's target inference, which predates this absorb. |
| Intro 2: "Skip the preamble and keep prose brief." | `visualize` Step 2 paragraph | Adapted | **Taken:** "place it beside the short text it supports"; the marketplace's own output posture already keeps prose brief. |
| Intro 3: "Pick the smallest view that makes the key point clear." | `visualize` Step 2 paragraph; [`code-shapes.md`](../../plugins/visualization/skills/visualize/context/code-shapes.md) "Selecting a view" | Taken verbatim | The family's selection heuristic. |
| Bullet: logic or an algorithm as pseudocode | Step 2 row; `code-shapes.md` "Pseudocode" | Taken verbatim | **Taken:** the `on(save)` example. **Narrowed:** the row reads "logic described in prose, or an algorithm before it is written", and Step 2 says pseudocode never paraphrases pasted code when a structural form answers the question, so the row cannot become a comprehension digest. |
| Bullet: runtime control flow as a call tree | Step 2 row; `code-shapes.md` "Call tree" | Taken verbatim | **Taken:** the `submitForm` example. The row is worded "a call path through named functions" so it does not overlap the mermaid row's domain flows. |
| Bullet: UI structure as a component tree with state and module boundaries | Step 2 row; `code-shapes.md` "Component tree" | Taken verbatim | **Taken:** the `<SessionPage>` example with its file paths. The spoke states that every path and identifier is a placeholder. |
| Bullet: file responsibility or a broad refactor as a shallow file tree | Step 2 row; `code-shapes.md` "Shallow file tree" | Taken verbatim | **Taken:** the `src/` example with box-drawing glyphs (upstream's own later correction, commit `4d8d644`: examples teach the glyphs agents emit). The catalog distinguishes it from the ASCII row's structure-only directory tree. |
| Bullet: component interaction, control flow, or data flow with Mermaid | existing Step 2 mermaid row | Not taken | **Rejected — already owned:** `visualize` has carried every mermaid family since 0.1.0; the upstream `sequenceDiagram` example adds nothing to the catalog. |
| Bullet: `diff` when the point is what changes and the surrounding shape already exists | Step 2 row; `code-shapes.md` "Diff-shaped delta" | Taken verbatim (rule) | **Taken:** the rule and the phrase "match the diff shape to the topic". The four sub-fences are rowed separately below. |
| Diff sub-fence: component change | `code-shapes.md` "A component change" | Taken verbatim | |
| Diff sub-fence: file-layout change | `code-shapes.md` "A file-layout change" | Adapted | **Changed:** `show-me.ts # expands the slash command` became `search.ts # parses the query`; the upstream line names the upstream command and would be provenance inside the skill. |
| Diff sub-fence: call-tree or call-stack change | `code-shapes.md` "A call-tree or call-stack change" | Adapted | **Changed:** the added `expandSkillMention` line became `validateInput`; the rest of the fence is verbatim. |
| Diff sub-fence: state or control-flow change | `code-shapes.md` "A state or control-flow change" | Taken verbatim | |
| Bullet: show the whole block when most of it is new, when omitted context would hide ownership or order, or when the user needs a copyable target shape | Step 2 row; `code-shapes.md` "The whole block" | Adapted | **Taken:** the three conditions, verbatim. **Changed:** the `expandSkill` example (which implements the upstream command) became a neutral `slugify` function. **Re-postured:** presented as the fallback among the sketches ("when no sketch is smaller than the code itself"), since a visual-form router emitting plain code needs a stated reason. |
| Bullet: one focused HTML file (diagram, infographic, short slide deck; match the product's colors, type, spacing, components; real labels and data; desktop and mobile), then `Bash(open …)` | existing Step 2 rich-page row; Step 5 page bullet; existing Step 3 ladder | Adapted | **Taken:** infographic and short slide deck as page genres on the rich-page row; product-matching, real data, desktop-and-mobile on the Step 5 page bullet. **Rejected — already owned:** the `Bash(open …)` step; the Step 3 ladder (Artifact, else local HTML file with placement and open rules, else terminal) predates this absorb and degrades where upstream cannot. |
| Guidance 1: "Place each visual next to the short text it supports." | `code-shapes.md` "Selecting a view"; Step 2 paragraph | Taken verbatim | |
| Guidance 2: "Keep only the calls, files, props, states, and boundaries needed to answer the user's current question or the options to resolve the current discussion point." | `code-shapes.md` "Selecting a view"; Step 2 paragraph (shortened) | Taken verbatim | |
| Guidance 3: "You may use one of these, you may use several, it is unlikely you will use all of them." | `code-shapes.md` "Selecting a view"; Step 2 paragraph ("one form, sometimes several, rarely all") | Taken verbatim | |
| Guidance 4: "Use your judgment and don't overwhelm the user." | `code-shapes.md` "Selecting a view" | Adapted | **Changed:** "don't" to "do not" (house style). |

Beyond the pinned file, two behaviors were added that upstream leaves implicit: a thin-context
prompt (one ranked question when pasted code fits several forms about equally, tunable through the
`thin_context_prompt` plugin option) and a terminal pin for pull-request diffs, fetched content, and
other repositories' files until the `visualize` skill is wired through the marketplace's
rendered-views escape helper. Neither is upstream content.

## License notice

The example blocks in `plugins/visualization/skills/visualize/context/code-shapes.md` carry text
from humanlayer/skills. Per the MIT condition, the upstream copyright line and permission notice
travel with them; they are recorded here and in the `visualization` plugin's CHANGELOG entry for
0.5.0 (the changelog ships with the installed plugin; this record does not). Nothing is placed in
the skill body or its spokes.

```text
Copyright (c) 2026 HumanLayer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Evaluated, not adopted yet: rpi and its structure-outline phase

Evaluated at `main@653b641` (2026-10-08T21:54:25Z), read 2026-10-10. `plugins/rpi/` was added by
upstream PR #13 (opened 2026-10-07, merged 2026-10-08); its eleven commits run from `e19a7a4`
(2026-10-05, "add portable rpi workflow entry skill") to `3b53bed` (2026-10-08). `plugin.json` says
version 1.0.0, license MIT. Files read in full: `skills/rpi/SKILL.md`, `references/workflow.md`,
`references/show-me.md`, the create and iterate `structure-outline` and `design-discussion` processes
and templates, `references/implement-outline/process.md` and `agents/outline-implementer-agent.md`.

**What it is.** One user-invoked skill (`/rpi`, "Only use when the user explicitly invokes this skill
by name") that routes to one `process.md` per phase: research questions, research, then a design
discussion, or a PRD followed by a TDD, or a TDD alone, then an optional structure outline, then
implementation. Each phase writes a numbered markdown document (`NN-<phase>-<slug>.md`) into a task
directory under `.agents/artifacts/`, runs in its own context window by default, and ends by printing
the next command with the task directory and the chosen flow. Five subagents (locator, analyzer,
pattern finder, web researcher, outline implementer) ship as agents and as reference copies for
hosts without them, so the same skill runs in Claude Code and Codex. `scripts/test-rpi-workflows.ts`
holds 52 live workflow tests run against fixture repositories.

**The structure-outline phase.** It turns the agreed design into ordered phases. Upstream text:
"Prefer small end-to-end results that cross the relevant module or service boundaries. Each phase
should work and be verifiable when it ends." Each phase carries its result and why it comes next, a
**Change Outline** drawn with the show-me views (file tree, contracts, call trees, pseudocode, focused
`diff` blocks), and **Validation** split into **Automated Verification** and **Manual Verification**
checkboxes. An **Implementation Overview** lists one unchecked item per phase, and **Open Questions**
holds unsettled scope. Frontmatter records `repos` with an `identifier` and `sha` for each
repository. Loading `show-me.md` is the "planning language" Dex Horthy refers to when he compares
html-plan to this phase ([post](https://x.com/dexhorthy/status/2107267652628672855), 2026-10-06; see
[`html-plan.md`](html-plan.md)).

**Design questions resolved with rationale.** The design discussion holds **Design Questions** (each
with options, tradeoffs and a recommendation grounded in the codebase) and **Resolved Design
Questions**. Upstream text: "Present one decision at a time with its options and recommendation, then
wait for the user's answer." On a decision it moves the choice to the resolved section and records
"the chosen approach, rationale, and why the alternatives were set aside."

Relation vocabulary as in [`mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md) (DERIVED,
PARTIAL, CONVERGENT, NONE). "Why upstream" is **stated** when the author says it (skill text, a test
name, or HumanLayer's [Advanced Context Engineering](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/ace-fca.md)
essay) and **inference** when it is derived from the mechanism. Disposition names the #6917
workstream that decides the row, or says none does.

| Upstream element | Why upstream (problem it removes) | Ours | Relation | Disposition |
|---|---|---|---|---|
| A phase chain with one document per phase, each phase in a fresh context, the next command printed with task directory and flow | The context window is "the ONLY lever you have"; compaction is "distilling them into structured artifacts" (essay). **Stated** | `/planning:interview` → `/planning:prd` → `/planning:design` → `/planning:plan` → `/work-items:decompose` → `/implementation:implement`; PLAN.md must let a cleared session execute from the file alone | CONVERGENT | **Already present.** W3 checks that every chain skill's `## Next` agrees with `/session-flow:workflow`. |
| Research questions written separately from the request; research does not load the request or design documents ("keep the desired change in the separate request document so research stays objective") | Facts bent by the intended change. Test `research-isolation` plants decoy request and PRD files. **Stated** | None in the planning chain; `/discovery:research` was not checked | NONE | **Not assigned** to a #6917 workstream. |
| Phase 4 of the outline: small end-to-end phases that cross module boundaries, each working and verifiable when it ends | Horizontal plans whose errors surface late. **Inference** | `/planning:plan` tracer-bullet and integration-first ordering with a sanity check per phase; `/work-items:decompose` thin vertical slices | CONVERGENT | **Already present.** |
| Change Outline per phase drawn with the show-me views and focused diffs | Prose or file-by-file changelogs hide the structure under review. **Inference** | `/visualization:visualize` code shapes (PARTIAL from show-me, table above); not used in PLAN.md | CONVERGENT | **Under evaluation, W6:** plans use the code-shape views with `@ path:line`. |
| Validation split into Automated and Manual Verification checkboxes; the implementer pauses for manual checks and marks a phase `✅` only after human confirmation | Running ahead on unverified work. Test `phase-pause-and-resume`. **Stated** | PLAN.md phase status tags and a mechanically verifiable sanity check per phase; no manual-check split | CONVERGENT | **Not assigned.** |
| `repos` frontmatter with `identifier` and `sha` per document | A reader cannot tell which code a document described. **Inference** | None | NONE | **Under evaluation, W5:** plans stamp the commit they were checked at. |
| Design Questions moved to Resolved Design Questions with the chosen approach, rationale and rejected alternatives | Settled choices re-argued in later sessions. **Inference** | `/planning:design` tracks resolved, directional and deferred decisions with a `Basis:` line; PLAN.md "Decisions made" table | CONVERGENT | **Already present** in shape. Recording why each alternative was set aside is not required by ours and is not assigned. |
| One decision per message, then wait | Users had to type "magic words" before the agent exposed its assumptions. Reported only in a [secondary write-up](https://www.zenml.io/llmops-database/evolution-from-rpi-to-crispy-multi-stage-workflow-for-production-coding-agents) of Dex Horthy's talk, not a primary quote | `/planning:interview` asks the whole frontier as a numbered round, each with a recommendation | CONVERGENT | **Kept different:** rounds are ours by design (Pocock `grilling` rows). |
| Document precedence for implementation: outline > TDD > PRD > design discussion > research > request, with the user's latest instruction winning | Conflicting documents with no tie-break. Test `document-precedence`. **Inference** | No stated precedence across Brief, PRD, design and PLAN.md | NONE | **Under evaluation, W4:** one artifact is declared the spec. |
| Outline implementer stops on a mismatch with "Expected / Found / Why this matters / How should I proceed?" | Silent deviation from the plan. **Stated** | `/implementation:implement` divergence detection routes back to planning; dispatched workers carry a divergence-escalation clause | CONVERGENT | **Already present.** |
| Task directory `.agents/artifacts/<slug>`, numbered documents, "recommend not committing the artifacts" | Writing into another task's documents. Tests `ambiguous-task-directory` and `main-branch`. **Stated** | Memory slice under `.work/` | CONVERGENT | **Already present.** |
| Portable across Claude Code and Codex: subagent reference copies, `<rpi-invocation>` placeholders checked by `scripts/sync-rpi-references.ts` | One skill text for several hosts. **Inference** from commit `04ecf04` | Claude Code only | NONE | **Not adopted:** this marketplace targets Claude Code. |
| Live workflow tests that drive a host on fixture repositories, each assertion naming a failure | Behavioral drift across models and hosts. **Inference** | Plugin eval suites for `plan` and `interview` | CONVERGENT | **Already present** in shape. |

**License.** `plugins/rpi/.claude-plugin/plugin.json` says MIT and the repository LICENSE is the MIT
notice reproduced below. Nothing from `rpi` is copied into this marketplace; if text is, the same
notice travels with it.

- **Pointer**: when re-deriving these rows, fetch
  <https://github.com/humanlayer/skills/tree/653b6411c1f70c275a18e37673b042ff99f67ceb/plugins/rpi>
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: a new commit under `plugins/rpi/` upstream after `3b53bed`
  (<https://github.com/humanlayer/skills/commits/main/plugins/rpi>).

## Not audited

The other plugins in the collection, `improve-claude-md`, `narrow-react-prop-types`,
`build-iterated-agentic-loop` and `visual-pr` (added in `4e39d8f`, 2026-09-17), were not evaluated
for this marketplace. This is not a "not adopted" verdict; nobody researched those lanes. Recheck
trigger: a change under any of those four `plugins/<name>/` paths upstream, or a request for one of
those lanes here.

## Evaluated, not adopted: design-control-loop

Evaluated at upstream commit `39fb327`, the only commit under `plugins/design-control-loop/`
(upstream `main` HEAD was `653b641` on 2026-10-08). Not adopted, wrapped, or depended on, because
it conflicts with this repository's lane rules on four topics:

- Loop shape: this marketplace's lanes are session-resident queue drains.
- Permission mode: `AGENTS.md` forbids bypass mode for lanes.
- Version pinning: lanes run pinned tools.
- Pull request text: lanes frame it as untrusted content.

The evaluation linked below records what upstream does on each topic.

One idea is worth tracking: a ceiling on open lane pull requests awaiting human review. It is
tracked separately and is not part of this record.

The evaluation is the Fighting Code Slop video digest, companion
`loop-engineering-control-loops.md` (item 11 verdict), in `melodic-software/knowledge-corpus`
(PR #43), under
`sources/videos/fighting-code-slop-the-state-of-software-ix1qQK1IvmA/analysis/companion/`.

- **Pointer**: when re-deriving this verdict, fetch the evaluated source
  <https://github.com/humanlayer/skills/tree/39fb32786ae7a7cd864cf2c237148c38b1e4db07/plugins/design-control-loop>
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: a new commit under `plugins/design-control-loop/` upstream after `39fb327`
  (<https://github.com/humanlayer/skills/commits/main/plugins/design-control-loop>).
