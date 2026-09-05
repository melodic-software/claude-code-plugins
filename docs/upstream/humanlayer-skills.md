# Upstream source — humanlayer/skills (show-me)

Single source of truth for everything in this marketplace derived from
[humanlayer/skills](https://github.com/humanlayer/skills) — "Claude Code skills from HumanLayer",
MIT — and specifically its `plugins/show-me/skills/show-me/SKILL.md`. The `visualization` plugin's
code-shape sketch family is inspired by and adapted from that skill. Provenance lives HERE and in
plugin CHANGELOGs, never in skill bodies, where it is agent-facing noise. Content citations an agent
actually uses are not provenance records and stay in place.

**Last audited upstream state:** `main@3c26291` (upstream HEAD at audit, the merge of its PR #5,
2026-08-13T15:05:30Z). `plugins/show-me/skills/show-me/SKILL.md` last changed at `6ab9013` and is
byte-identical at that HEAD. "v1.0.1" is the plugin manifest version; the repository has no git
tags. Git history of this file records *when*; this line records only *what was audited*.

**Recheck trigger:** a change to `plugins/show-me/skills/show-me/SKILL.md` against `6ab9013` — re-audit
the affected rows below. The upstream publishes no release notes and no tags, so the trigger is a
file change rather than a release, and the audit is a diff against the pinned commit.

**Adaptation posture.** Every example block and guidance sentence that fit this marketplace's
`visualize` router was carried **verbatim**; three example blocks were **adapted** because as written
they describe implementing the upstream slash command itself; the surrounding prose was reauthored to
the router's structure and house style. The upstream skill is not shipped, wrapped, or depended on:
its trigger vocabulary ("show me", "sketch", "diagram") was already owned by `visualize`, the
marketplace's skill-split rule admits a second skill only on distinct triggers, and the listing
aggregate for the neighbouring plugins is over budget. Bare `/show-me` is therefore not a command in
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
| Guidance 4: "Use your judgement and don't overwhelm the user." | `code-shapes.md` "Selecting a view" | Adapted | **Changed:** "don't" to "do not" (house style). |

Beyond the pinned file, two behaviors were added that upstream leaves implicit: a thin-context
prompt (one ranked question when pasted code fits several forms about equally, tunable through the
`thin_context_prompt` plugin option) and a terminal pin for pull-request diffs, fetched content, and
other repositories' files until the marketplace's rendered-views escape helper ships. Neither is
upstream content.

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

## Not audited

The other four plugins in the collection, `improve-claude-md`, `narrow-react-prop-types`,
`build-iterated-agentic-loop`, and `design-control-loop`, were not evaluated for this marketplace.
This is not a "not adopted" verdict; nobody researched those lanes. Recheck trigger: a change under
any of those four `plugins/<name>/` paths upstream, or a request for one of those lanes here.
