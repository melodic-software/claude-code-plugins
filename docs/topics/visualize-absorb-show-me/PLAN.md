# visualize-absorb-show-me

## Brief

### TLDR

- Absorb the humanlayer `show-me` skill's code-shape sketch family into `plugins/visualization/skills/visualize` as new Step 2 form rows plus a new examples spoke; the upstream skill itself is not shipped, wrapped, or depended on.
- Make form selection context-driven: render without asking when the conversation already fixes target and form; offer one short ranked menu when pasted content arrives with thin context and no named form.
- Carry the upstream pieces that work verbatim into the skill and spoke; keep every trace of provenance, citation, and licensing OUT of the skill and its spokes. Provenance lives only in a new `docs/upstream/humanlayer-skills.md` and the plugin CHANGELOG.
- Fix the catalog facts found in passing (dead output-styles citation, stale CSP sentence, mermaid runtime recorded as version-specific, public-sharing bug listed as an open issue) in the same PR.
- Bump `visualization` to 0.5.0; add five evals (8-12) and a `thin_context_prompt` option; no ADR, no LICENSE file, no native-surfaces registry row.

### Goal

A user who has just discussed a change set, an algorithm, a call path, a UI structure, or a file layout can invoke `/visualization:visualize` (or have it fire on "show me the shape of this") and receive the smallest code-shaped view that makes the point, in the terminal, chosen from the conversation's own context. When the context is thin, they get one question listing the fitting forms with a recommendation first, never a guess and never an interrogation. The upstream skill is fully absorbed: every form and every guidance rule it carries has a landing point in ours, and the merged skill reads as one coherent router rather than a bolt-on. The plugin's existing behavior for its existing forms (mermaid, tables, charts, ASCII, rich page, design canvas, medium ladder, playground boundary) is unchanged; the rich-page row gains upstream's page genres and product-matching guidance, and the only new delivery rule pins PR diffs, fetched content, and other repositories' files to the terminal.

### Constraints

- **No provenance in the skill.** `SKILL.md`, `context/decision-matrix.md`, `context/code-shapes.md`, and `evals/evals.json` carry no attribution, citation of humanlayer, license text, or "adapted from" language. The repo's existing rule ("provenance lives in docs/upstream and CHANGELOGs, never in skill bodies") applies without exception.
- **No LICENSE file** in `plugins/visualization`. The MIT notice condition is met by carrying HumanLayer's copyright line and the MIT permission notice in two places that are not the skill: `docs/upstream/humanlayer-skills.md` (the repo record) and the `## [0.5.0]` entry of `plugins/visualization/CHANGELOG.md`, because the CHANGELOG is the only provenance-carrying file that ships in an installed copy of the plugin (verified: the plugin cache holds `.claude-plugin/`, `CHANGELOG.md`, `README.md`, `skills/` and nothing from `docs/`). *(Amended after stress-test finding H5; the interview had placed the notice in docs/upstream only.)*
- **Verbatim where it works.** Upstream example blocks and guidance sentences that fit are carried as-is; rewrite only to fit our router's voice, structure, or the em-dash policy, never to launder provenance.
- **Comprehension disclaimers stay.** The "Not comprehension digest" bullet, the "Does not digest or re-explain dense text" bullet, the README's "not a comprehension aid", and the description's closing disclaimer all survive; the closing clause may be shortened to fit the codepoint cap but keeps both halves (not chart craft; not restating dense text). The new rows are content-shape → form rows and a selection heuristic, not "help the user understand" framing. Pseudocode is for logic described in prose or not yet written, never a paraphrase of pasted code.
- **Code-shape forms ride the existing medium ladder; only the baseline's named content class is pinned to the terminal.** The user keeps the choice they already have: under `auto` a fenced text form renders in the terminal (Step 3 rung 4 already says so for short code); an explicit `file`/`artifact` argument or the configured `medium` preference is honored for these forms exactly as for a table or ASCII sketch. The one exception is content the rendered-views security baseline names as attacker-controlled: a PR diff, fetched content, or another repository's files are never rendered to HTML until the escape helper ships, and that exception overrides rung 1 and the preference with a one-line visible notice (`docs/conventions/rendered-views/README.md`, security baseline). The exception is defined by content origin class, not by "repository-authored", which the stress test showed is not a trust boundary. *(Refined after stress-test finding H6 and the user's direction to keep user choice and prescribed defaults rather than add a blanket restriction.)*
- **User choice through plugin options, not new branches.** The existing `medium` option governs delivery for the new forms. One new option, `thin_context_prompt` (`auto` default: ask only when two or more code-shape forms fit pasted code about equally; `always`: offer the ranked menu on any bare code paste; `never`: render the recommended form without asking), governs the prompting behavior. Both are trivial scalars with defaults that preserve today's behavior, so no `setup` skill is owed (plugin philosophy, configuration ownership).
- **Merge, do not drop, upstream context that integrates.** Upstream's HTML bullet (an infographic or short slide deck as page genres; match the product's own colors, type, spacing, and components when the subject is a product UI; real labels and data; desktop and mobile) is folded into the existing rich-page row and Step 5, not marked "not taken". Only the comprehension framing ("Help the user understand…") is left out, because the skill's declared boundary excludes it.
- **Skill-quality gate.** Description at or under 1024 codepoints (a 2b WARN is acceptable only if the trimmed clause cannot cover it, and then the PR body says so); never over 1536; all ten existing quoted triggers preserved (check 3); every new `context/` file cited from the body (checks 5, 15); SKILL.md under 500 lines; `disable-model-invocation: false` kept explicit; `metadata.summary` under 100 codepoints.
- **Prose policy.** Zero em dashes in `SKILL.md` and `README.md` (the purge gate); the new spoke follows the same house style even though it is not on the purge list. Upstream text is reference, not style.
- **Changelog parity and delivery.** Manifest 0.4.2 → 0.5.0 with a new `## [0.5.0]` heading, `### Added` and `### Fixed`; `docs/CATALOG.md` regenerated if `plugin.json`'s description changes; README's skill-table prose and form table updated to name the new family (README line 3 "One skill, one job" unchanged).
- **Untouchable.** Step 3's medium ladder (rungs 1-4, cascade, surface gate, page chrome, local-file placement), the playground Boundary section, the design-canvas row, and the `medium` userConfig's values and default. The only addition to Step 3 is the one sentence pinning the baseline's attacker-controlled content class to the terminal, which changes nothing for any other content.

### Acceptance criteria

- `SKILL.md` Step 2 has new rows for: logic or an algorithm → pseudocode; runtime control flow → call tree; UI structure with state and module boundaries → component tree with file paths; file responsibility or refactor scope → shallow file tree with one-line responsibilities; the shape of code before it exists → types and signatures; what changes when the surrounding shape already exists → a diff-shaped delta over any of the above; mostly-new or copyable target → the whole block. HTML mockups and mermaid are not added (already covered).
- Step 2 states the selection heuristic: pick the smallest view that makes the key point clear; place each visual beside the short text it supports; keep only the calls, files, props, states, and boundaries the question needs; use one form, sometimes several, rarely all.
- Step 1 says the target is read from the chat history first (a change set just discussed → the diff-shaped delta; a described algorithm → pseudocode). Step 4 has a thin-context branch: when content arrives with little context and no form named, ask one question listing the two to four fitting forms with the recommended one first.
- `context/code-shapes.md` exists, is cited from Step 2, and carries one example per form using real box-drawing glyphs (`├── │ └──`), with diff examples for the component, file-layout, call-tree, and state shapes.
- `context/decision-matrix.md`: the ASCII row distinguishes a structural directory sketch from the responsibility-per-entry file tree; the output-styles citation is replaced by the binary and issue evidence; the CSP sentence matches the current artifacts page (Google Fonts plus cdnjs, jsDelivr `/npm/`, Tailwind CDN, jQuery CDN allowed, everything else blocked); mermaid 11.16.1 is recorded as a four-part version-specific record (claim, basis, as-of, per-release recheck trigger); the public-sharing bug is in the UNVERIFIED list as an open issue.
- Description: "code-shape sketches" appears in the form list; `'show me the shape of this'` is a quoted trigger; all ten existing quoted triggers are present; codepoint count ≤ 1024 (or the WARN is stated in the PR body).
- `evals/evals.json` has five new cases with unique ids 8-12 and unique names: a prose-described algorithm renders pseudocode in the terminal and no page; "what changes if we add X" over a shape already in the conversation renders a diff-shaped delta; a small question gets exactly one form; pasted code with thin context where two or more code-shape forms fit gets one ranked-menu question (under the default `thin_context_prompt: auto`) and no paraphrase into pseudocode; a pasted PR diff with an explicit `artifact` argument stays a terminal fence with a one-line notice and no page.
- `plugin.json` `userConfig` gains `thin_context_prompt` (string, default `auto`, values `auto`/`always`/`never`, validated in-skill like `medium`); Step 4 reads `${user_config.thin_context_prompt}` with the same unset-token handling as `medium`; the README options block is regenerated by `scripts/sync-plugin-options-docs.py` and its hand-written Configuration section documents the option.
- The rich-page row and Step 5 carry upstream's page specifics: an infographic or short slide deck are named page genres; when the subject is a product UI, match that product's colors, type, spacing, and components (the plugin chrome remains the default for everything else); real labels and data; desktop and mobile. Existing evals 1, 2, 3 are the named regression guards (a described process still picks mermaid without a question; a pasted comparison still renders a table without a question; pasted numbers still render a chart without a question). Schema-valid; `check-evals-quality.sh` passes.
- **Coverage check.** `docs/upstream/humanlayer-skills.md` has an attribution table whose "What was taken" column maps every element of the pinned upstream `SKILL.md` (eight form bullets, the HTML-file bullet, and each sentence of the `### guidance` section) to its landing point in our skill, or records why it was not taken (HTML file → existing Step 3 ladder; mermaid → existing row). No element is unaccounted for.
- `docs/upstream/humanlayer-skills.md` follows the cursor-pstack shape: title, source paragraph with "inspired by and adapted from", pinned `main@6ab9013`, recheck trigger (a change to `plugins/show-me/skills/show-me/SKILL.md` against the pin), adaptation posture (verbatim-where-it-works, reauthored elsewhere), the attribution table, HumanLayer's copyright line and MIT permission notice, and a one-line "not audited" note naming `improve-claude-md`, `narrow-react-prop-types`, `build-iterated-agentic-loop`, and `design-control-loop`.
- `CHANGELOG.md` gains `## [0.5.0]` with `### Added` (the form family, the spoke, the thin-context branch, the evals, citing the upstream record) and `### Fixed` (the four catalog corrections). `plugin.json` version is 0.5.0. `check-changelog-parity.sh --check-bump origin/main` passes.
- `README.md` names the code-shape family in the skill table and the form table; "One skill, one job" is unchanged; zero em dashes in hand-written prose.
- Grep proof: no occurrence of `humanlayer`, `show-me`, `horthy`, `license`, `adapted from`, or `inspired` (case-insensitive) and no whole-word case-sensitive `MIT` under `plugins/visualization/skills/` or in `plugins/visualization/README.md`. The CHANGELOG is excluded from this proof by design (it carries the notice).
- Gates green locally: `check-skill.sh --require-evals visualize` (0 errors), `check-evals-quality.sh`, `check-purged-em-dashes.sh`, `check-changelog-parity.sh`, `generate-catalog.mjs --check`, `generate-cheatsheet.mjs --check`, `check-skill-count-claims.sh --check`. `check-skill.sh` needs a background run on this machine (it exceeds a 120 s foreground timeout).

### Captured assumptions

- The artifacts page's CSP allowlist as re-fetched 2026-09-04 is current — revisit if the artifacts page's "Page constraints" or "Allowlist the viewer domain" section changes.
- Public sharing of an artifact is reported to fail for pages containing mermaid blocks, SVG data URIs, or AVIF images (anthropics/claude-code#79824 open; #81410 sibling); the mechanism is unconfirmed — revisit when either issue closes or a changelog entry names artifact public sharing.
- Adding one trigger and one form-list phrase is paid for by trimming the description's closing clause; the exact edit in Phase 3.1 was measured at 1024 codepoints this session — revisit if the implementer's count differs; then accept the WARN and state it in the PR body.
- The bundled mermaid runtime is stamped against the Claude Code version installed at commit time (2.1.260 as of 2026-09-04, still 11.16.1) — revisit when the artifacts page or changelog names the runtime, when a mermaid-family rendering failure is reported, or at each `visualization` release.
- Upstream pin `main@6ab9013` (v1.0.1) is the latest show-me state — revisit if `plugins/show-me/skills/show-me/SKILL.md` changes upstream.

### Out-of-scope

- Wrapping or depending on the upstream plugin; any presence gate on an installed `show-me`.
- A sibling skill, an ADR, a `plugins/visualization/LICENSE`, a native-surfaces registry row.
- Auditing the other four humanlayer/skills plugins (recorded as "not audited", not "not adopted").
- Rendering PR diffs or fetched content to HTML (gated on the escape helper).
- Changing the medium ladder, the playground boundary, the design-canvas row, or the `medium` option.
- Bare `'show me'` as a trigger (collides with four other plugins' listings).
- Rewriting the comprehension disclaimers.

### Deferred questions

None. Every registered question (Q1-Q13) is answered in `.work/visualize-absorb-show-me/interview-checklist.md`. Execution-shape choices left to `/planning:plan` (exact row wording, spoke section order, which upstream blocks are carried verbatim versus adapted, the precise description trim) stay within the acceptance criteria above and need no re-confirmation.

## Plan

### Goal

**What**: add the code-shape sketch family (seven forms plus a selection heuristic and a thin-context menu) to `visualize`, backed by a new examples spoke, an evals set, a provenance record outside the plugin, and four catalog corrections, shipped as `visualization` 0.5.0.
**Why**: the fleet has no home for "show me the shape of this" (pseudocode, call trees, component and file trees, diff-shaped deltas), and the one skill that owns form selection should carry it rather than a second skill or a wrapped dependency.

### Standards grounding

No `.claude/standards.yaml` and no `docs/standards/README.md` exist (ladder rungs 1-3 absent). Inferred from repository context (rung 4): the repo's normative surfaces are `docs/PLUGIN-PHILOSOPHY.md` and `docs/conventions/*`, already loaded through the exploration artifact. Offer to persist an index is deferred to the presentation.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Design boundary (org-agnosticism), Naming, Instruction economy | team |
| `docs/conventions/rendered-views/README.md` | genre rubric, 40-line lane cap, security baseline (PR diff gated on escape helper) | team |
| `docs/conventions/upstream-drift/README.md` | four required parts, observability bar, Adopters | team |
| `docs/conventions/seam-phrasing/README.md`, `invocation-mode/README.md` | no new cross-plugin gate is added; `disable-model-invocation: false` stays explicit | team |
| `docs/conventions/commit-convention/README.md`, `.claude/rules/pr-body-contract.md` | `feat(visualization): ...`; PR body opens with `No related issue: <reason>` | team |
| `.claude/rules/vendor-docs-are-not-style.md` | upstream text is reference; house prose style in SKILL.md and README | team |
| `docs/upstream/cursor-pstack.md` | record shape for a reauthored/verbatim-carried upstream skill | team |

### Approach

Order is Red then Green: the examples spoke and the evals land before the skill body changes, so the gates that grade the body (check 5, check 15, the evals) exist when the body is edited.

### Phase 1: Examples spoke `context/code-shapes.md` [DONE]

Create `plugins/visualization/skills/visualize/context/code-shapes.md`. One `##` section per form, in this order: pseudocode; call tree; component tree; shallow file tree; types and signatures; diff-shaped delta (four sub-examples: component, file layout, call tree, state or control flow); whole block. Each section: one line naming the content shape it fits, one fenced example. Carry these upstream example blocks verbatim (checked: no provenance tokens, no em dashes): the `on(save)` pseudocode, the `submitForm` call tree, the `<SessionPage>` component tree, the `src/` file tree, the component diff, and the state diff. Adapt these three, because as written they describe implementing the upstream slash command: the file-layout diff (rename `show-me.ts` to a neutral module such as `search.ts # parses the query`), the call-tree diff (rename its added `expandSkillMention` line to a neutral step such as `validateInput`; the rest of that fence stays as upstream wrote it), and the whole-block `expandSkill` function (replace with a neutral small function). Open the spoke with one line stating that every path and identifier in the examples is a placeholder, not a reference to a real file, so the example paths (`apps/example/src/routes/session.tsx`, `packages/ui`) do not read as ghost references under the repo's audit-noise standard. [EXEC-SHAPE] Write our own types-and-signatures example (upstream has none in the skill file). Present the whole block as the fallback, "when no sketch is smaller than the code itself", not as a peer form. Real box-drawing glyphs (`├── │ └──`) in every tree. Close with a short "Selecting a view" section carrying the four rules: smallest view that makes the key point clear; place each visual beside the short text it supports; keep only the calls, files, props, states, and boundaries the question needs; use one form, sometimes several, rarely all. House prose style (no em dashes), no provenance of any kind. Record verbatim-vs-adapted per block in the Phase 5 attribution table.

- **Sanity Check:** `test -f plugins/visualization/skills/visualize/context/code-shapes.md`
- **Sanity Check:** `grep -c "^## " plugins/visualization/skills/visualize/context/code-shapes.md` returns 8 (seven forms plus "Selecting a view")
- **Sanity Check:** `grep -c "├──" plugins/visualization/skills/visualize/context/code-shapes.md` ≥ 2 and `grep -c '|--' ...` returns 0
- **Sanity Check:** `! grep -qiE "humanlayer|show-me|horthy|license|adapted from|inspired" plugins/visualization/skills/visualize/context/code-shapes.md && ! grep -qw "MIT" plugins/visualization/skills/visualize/context/code-shapes.md` exits 0
- **Sanity Check:** `! grep -q "—" plugins/visualization/skills/visualize/context/code-shapes.md` exits 0

### Phase 2: Evals first (Red) [DONE]

Append five cases to `plugins/visualization/skills/visualize/evals/evals.json`, ids 8-12, `files: []`, matching the existing key shape (`id`, `name`, `prompt`, `expected_output`, `files`, `expectations`, plus `narration: true` on any case whose prompt or expectations quote a file path, so `check-evals-quality` Q4 does not flag prose paths):

- 8 `algorithm-renders-pseudocode-in-terminal`: a prose-described retry-with-backoff loop, no code pasted; expects a pseudocode fence in the terminal, no page, no mermaid.
- 9 `delta-over-known-shape-picks-diff-sketch`: a component tree already in the conversation, then "what changes if we add a toolbar button"; expects a diff-shaped delta over the tree, not a fresh full tree (`narration: true`).
- 10 `smallest-view-restraint`: a small "where does session state live" question; expects exactly one form (a shallow file tree), not a menu of several (`narration: true`).
- 11 `thin-context-code-paste-offers-ranked-menu`: a pasted 40-line function with no ask and no prior context, where call tree, types and signatures, and whole block all fit; expects one question listing two to four fitting forms with a recommended one first, no rendering before the answer, and no paraphrase of the function into pseudocode.
- 12 `diff-with-artifact-argument-stays-terminal`: a pasted unified diff plus the `artifact` argument; expects a terminal diff-shaped fence plus a one-line notice that code-shape forms stay in the terminal, and no page or Artifact.

Also reword existing eval 4's third expectation from "Does not ask when the target is obvious or a form was named" to "Does not ask when the target is obvious and one form dominates, or a form was named", so it no longer contradicts eval 11 (obvious target, two or more code-shape forms fitting equally).

- **Sanity Check:** `PYTHONUTF8=1 python3 -c "import json;d=json.load(open('plugins/visualization/skills/visualize/evals/evals.json',encoding='utf-8'));ids=[e['id'] for e in d['evals']];names=[e['name'] for e in d['evals']];assert ids==list(range(1,13)) and len(set(names))==12"` exits 0
- **Sanity Check:** `check-jsonschema --schemafile plugins/skill-quality/reference/evals.schema.json plugins/visualization/skills/visualize/evals/evals.json` exits 0
- **Sanity Check:** `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/visualization/skills/visualize/evals/evals.json` exits 0

### Phase 3: Skill body (Green) [DONE]

Edit `plugins/visualization/skills/visualize/SKILL.md`:

1. **Description** (line 2): in the form list, replace "ASCII/Unicode art" with "ASCII/Unicode art, code-shape sketches"; append `'show me the shape of this'` to the quoted trigger list; shorten the closing clause ("Not for polishing a specific chart's colors/axes (a chart-craft/dataviz capability owns that) or restating dense text in plainer words (a comprehension/digest concern).") to exactly "Not for chart craft (a dataviz capability owns it) or restating dense text in plainer words (a comprehension concern)." Computed this session: the current description is 1024 codepoints; the two additions cost 30 and the trim saves 30, landing at exactly 1024 (the earlier draft with "owns that" landed at 1026). All ten existing quoted triggers stay verbatim.
2. **Step 1**: add one sentence that the target is read from the chat history first (the thing just discussed, pasted, or changed). No form is pre-selected here; form is Step 2's decision.
3. **Step 2**: add seven rows to the form table after the ASCII row, worded by content origin so they do not overlap the mermaid row's "flow, process, hierarchy, sequence, state" (which stays for domain processes, sequences, and state machines): logic described in prose, or an algorithm before it is written → pseudocode; a call path through named functions → call tree; a UI's component tree with the state hooks and module boundaries that matter → component tree with file paths; where things live, or the scope of a refactor → shallow file tree, one line of responsibility per entry; the shape of code before it exists → types and signatures; what changes when the surrounding shape is already in the conversation → diff-shaped delta over any of these; and, as the fallback when no sketch is smaller than the code → the whole block. Add a tie-break sentence: when the content is code (named functions, files, components, types) prefer a code-shape row; when it is a process, sequence, or state in the domain, prefer mermaid; pseudocode never paraphrases pasted code when a structural form answers the question. Reword the ASCII row to "Small structural sketch, box layout, a directory tree as structure" so the responsibility file tree is unambiguous. Add one paragraph after the table: code-shape sketches are fenced text and need no rendering surface; pick the smallest view that makes the key point clear, place it beside the short text it supports, keep only what the question needs, use one form, sometimes several, rarely all; examples per form in [`context/code-shapes.md`](context/code-shapes.md).
4. **Step 3**: one sentence after the surface gate: code-shape forms take the same ladder as every other form (under `auto` a fenced text form stays in the terminal, per rung 4; `file`/`artifact` and the configured preference are honored), except that a PR diff, fetched content, or another repository's files are never rendered to HTML until the rendered-views escape helper ships; that exception overrides rung 1 and the preference, and the skill says so in one line when a page was asked for.
5. **Step 4**: extend the existing form-ambiguity bullet rather than adding a new branch, gated by `${user_config.thin_context_prompt}` (same unset-token handling as `medium`; unrecognized values reported and treated as `auto`): under `auto`, pasted code with little conversational context and no named form, where two or more code-shape forms fit about equally, gets one question listing those two to four forms, recommended one first, while one dominant form renders without asking (a table is a table, a chart is a chart, evals 2 and 3 are the guards); under `always`, any bare code paste gets the ranked menu; under `never`, the recommended form renders without asking. Never a form-by-form interrogation, never a render before the answer when a question is asked.
6. **What this skill does NOT do**: add "Does not render a PR diff, fetched content, or another repository's files to HTML until the rendered-views escape helper ships." (This names the baseline's content class for every form; it narrows no existing path because the baseline already governed it.)
7. **Rich-page row and Step 5**: the rich-page row names an infographic and a short slide deck as page genres beside the composite and interactive views; Step 5's page bullet adds: when the subject is a product UI, match that product's own colors, type, spacing, and components (the plugin chrome stays the default otherwise); use real labels and data; support desktop and mobile. Two or three lines total.

Line budget: expect ~255 lines (soft target 200 already exceeded; hard cap 500). The added standing text totals about 30 lines; the PR body names the stumble evidence (the user's reported experience of prose walls where a shape would do, and the upstream's adoption) per the instruction-economy rule.

- **Sanity Check:** `sed -n '2p' plugins/visualization/skills/visualize/SKILL.md | python3 -c "import sys;s=sys.stdin.read().strip();v=s[len('description: '):].strip('\"');print(len(v));assert len(v)<=1024"` exits 0 (or, if it cannot fit, the PR body states the 2b WARN and the count is < 1536)
- **Sanity Check:** `grep -c "'show me the shape of this'" plugins/visualization/skills/visualize/SKILL.md` returns 1 and `grep -c "code-shape sketches" ...` ≥ 1
- **Sanity Check:** `grep -c "context/code-shapes.md" plugins/visualization/skills/visualize/SKILL.md` ≥ 1
- **Sanity Check:** `grep -c "Not comprehension digest" plugins/visualization/skills/visualize/SKILL.md` returns 1 and `grep -c "Does not digest or re-explain dense text" ...` returns 1
- **Sanity Check:** `grep -c "escape helper" plugins/visualization/skills/visualize/SKILL.md` ≥ 1, `grep -c "two to four" ...` ≥ 1, `grep -c 'user_config.thin_context_prompt' ...` returns 1, and `grep -c "slide deck" ...` ≥ 1
- **Sanity Check:** `! grep -qiE "humanlayer|show-me|horthy|license|adapted from|inspired" plugins/visualization/skills/visualize/SKILL.md && ! grep -qw "MIT" plugins/visualization/skills/visualize/SKILL.md` exits 0
- **Sanity Check:** `CHECK_SKILL_BASE_REF=origin/main CHECK_SKILL_SKIP_MARKDOWNLINT=1 CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/visualization/skills" bash plugins/skill-quality/scripts/check-skill.sh --require-evals visualize` reports `0 errors` and `all 10 base-ref trigger phrase(s) preserved` (run in the background; it exceeds a 120 s foreground timeout on Windows)

### Phase 4: Catalog corrections and the code-shape entry [DONE]

Edit `plugins/visualization/skills/visualize/context/decision-matrix.md` (not on the em-dash purge list; existing em dashes stay, new text has none):

1. CSP, five sites: line 27 ("every external host is blocked — no CDN scripts, stylesheets, fonts, remote images"), lines 35-36 (connector paragraph: "the page itself makes no network call" becomes "the page itself makes no data call; it hands each call to claude.ai"), line 102 ("the CSP blocks every CDN"), line 182 ("which the artifact CSP blocks outright"), and line 198 in Sources ("Artifact CSP (no external requests, inline CSS/JS …)" becomes "Artifact CSP (Google Fonts plus four CDN script hosts allowed, everything else blocked; this plugin inlines regardless)"). Replace with the current contract: Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`) and scripts from `cdnjs.cloudflare.com`, `cdn.jsdelivr.net` (`/npm/` paths), `cdn.tailwindcss.com`, `code.jquery.com` are allowed; every other external image, script, stylesheet, and font is blocked; `fetch`/XHR/WebSocket reach only the page's own origin and the Google Fonts hosts. State "inline everything, no network calls" as this plugin's own self-containment policy (the README promises it), not as a platform fact. Line 182's third-party-plugin disqualification changes from "the CSP blocks CDN libraries outright" to "pulls chart libraries from hosts outside the artifact allowlist, and this plugin's policy is no network calls". Verified 2026-09-04 against `https://code.claude.com/docs/en/artifacts`; recheck trigger: the artifacts page's "Page constraints" or "Allowlist the viewer domain" section changes.
2. "Form catalog": after the ASCII entry, add a "Code-shape sketches" entry: fenced text forms (pseudocode, call tree, component tree, shallow file tree, types and signatures, diff-shaped delta, whole block) that render in any GFM surface and need no page; the ASCII entry keeps directory trees as structure, the file-tree form carries one responsibility per entry.
3. Sources: replace the `output-styles.md` citation for "mermaid emitted as source" with the actual basis, scoping the absence claim: `https://code.claude.com/docs/en/interactive-mode.md` and `https://code.claude.com/docs/en/fullscreen.md` (both fetched whole 2026-09-04, zero occurrences of "mermaid") and the `llms-full.txt` corpus sweep (one hit, an output-style example, not a rendering statement) document no terminal mermaid rendering; the shipped binary carries no terminal-side renderer (all mermaid strings are artifact-side); anthropics/claude-code#14375 (open) requests terminal rendering and #52517 (open) reports Claude Desktop's Claude Code tab showing a mermaid fence as raw source. Verified 2026-09-04; recheck trigger: a changelog entry or either page naming terminal diagram rendering, or #14375 closing.
4. Mermaid runtime, four sites: add a four-part version-specific record to the "Published Artifact" section (the Artifact publish path injects mermaid 11.16.1; basis: `grep -a` of the installed Claude Code binary for `/_runtime/mermaid-` at commit time, the version stamped is the one installed then, 2.1.260 at planning time; as-of the commit date; recheck triggers: the artifacts page or changelog names the runtime, a mermaid-family rendering failure is reported, or each `visualization` release); reword line 70 ("The bundled renderer's version is undocumented (see below)") and line 91 ("the bundled mermaid version is undocumented") to "not documented by the platform; read from the binary, see the Published Artifact record"; reword the "fire-icon families" bullet to "present in mermaid 11.16.1 upstream; rendering in the artifact viewer unverified"; remove the mermaid-version bullet from the UNVERIFIED list (a verified record does not belong there).
5. UNVERIFIED list: add "public sharing of an artifact is reported to fail for pages containing mermaid blocks, SVG data URIs, or AVIF images (anthropics/claude-code#79824 open, #81410 sibling, as of 2026-09-04); mechanism unconfirmed; private and org sharing unaffected; recheck when either issue closes or a changelog entry names artifact public sharing".

- **Sanity Check:** `! grep -q "every external host is blocked" plugins/visualization/skills/visualize/context/decision-matrix.md && ! grep -q "blocks every CDN" ... && ! grep -q "blocks outright" ... && ! grep -q "no external requests" ... && ! grep -q "makes no network call" ... && ! grep -q "version is undocumented" ...` exits 0 and `grep -c "cdnjs" ...` ≥ 1
- **Sanity Check:** `! grep -q "output-styles" plugins/visualization/skills/visualize/context/decision-matrix.md` exits 0 and `grep -c "14375" ...` ≥ 1
- **Sanity Check:** `grep -c "11.16.1" plugins/visualization/skills/visualize/context/decision-matrix.md` ≥ 1 and `grep -c "79824" ...` ≥ 1 and `grep -a -c "/_runtime/mermaid-11.16.1" "$(readlink -f "$(command -v claude)")"` ≥ 1 after confirming that path is the real binary (over 100 MB), not an fnm or npm shim; if the count is 0 on the real binary, stamp the version it reports instead
- **Sanity Check:** `grep -c "### Code-shape sketches" plugins/visualization/skills/visualize/context/decision-matrix.md` returns 1
- **Sanity Check:** `! grep -qiE "humanlayer|show-me|horthy" plugins/visualization/skills/visualize/context/decision-matrix.md` exits 0

### Phase 5: Provenance record `docs/upstream/humanlayer-skills.md` [DONE]

Create the record in the cursor-pstack shape: title `# Upstream source — humanlayer/skills (show-me)`; source paragraph naming the repo, MIT, "inspired by and adapted from", and the rule that provenance lives here and in the CHANGELOG, never in skill bodies; `**Last audited upstream state:** main@3c26291` (upstream HEAD at audit, the merge of its PR #5, 2026-08-13T15:05:30Z; `plugins/show-me/skills/show-me/SKILL.md` last changed at `6ab9013`, byte-identical at HEAD; "v1.0.1" is the plugin manifest version, the repo has no git tags); `**Recheck trigger:**` a change to `plugins/show-me/skills/show-me/SKILL.md` against `6ab9013`; `**Adaptation posture.**` verbatim where an example or sentence fits our router, reauthored where our structure or house style requires, no upstream skill shipped; `## Attribution table` with one row per upstream element, enumerated from the pinned file: the frontmatter description (1), the three intro sentences "Help the user understand…", "Skip the preamble…", "Pick the smallest view…" (3), the eight bullets including the HTML-file bullet (8), the four diff sub-fences (4), and the four `### guidance` sentences (4), twenty rows in all, each mapping to its landing point (`SKILL.md` Step 2 row or heuristic, `context/code-shapes.md` section, existing Step 3 ladder for the HTML file, existing mermaid row) with Relation "Taken verbatim", "Adapted", or "Not taken" plus the reason ("Help the user understand…" is the one not-taken element: comprehension framing outside the skill's declared boundary; the HTML-file bullet is "Adapted" into the rich-page row and Step 5, with the `Bash(open …)` step already covered by the existing ladder); `## License notice` carrying `Copyright (c) 2026 HumanLayer` and the MIT permission notice verbatim; `## Not audited` naming `improve-claude-md`, `narrow-react-prop-types`, `build-iterated-agentic-loop`, `design-control-loop`, with its own recheck trigger (a change under any of those four `plugins/<name>/` paths upstream, or a request for one of those lanes). The attribution table's Relation column distinguishes "Taken verbatim" from "Adapted" per block, matching Phase 1. The Adopters table in `docs/conventions/upstream-drift/README.md` does not list `cursor-pstack.md` (verified 2026-09-04), so no row is added there.

- **Sanity Check:** `grep -c "main@3c26291" docs/upstream/humanlayer-skills.md` returns 1 and `grep -c "6ab9013" docs/upstream/humanlayer-skills.md` ≥ 1
- **Sanity Check:** `grep -c "Copyright (c) 2026 HumanLayer" docs/upstream/humanlayer-skills.md` returns 1 and `grep -c "Permission is hereby granted" ...` returns 1
- **Sanity Check:** `awk '/^## Attribution table/{f=1} /^## /&&!/Attribution/{f=0} f&&/^\| /' docs/upstream/humanlayer-skills.md | wc -l` returns 21 (twenty element rows plus the header row; the `|---|` separator does not match `^| `)
- **Sanity Check:** `grep -c "not audited" docs/upstream/humanlayer-skills.md` ≥ 1

### Phase 6: README, CHANGELOG, manifest, generated catalog [DONE]

1. `plugins/visualization/README.md`: skill-table row (line 9) lists "code-shape sketch" among the forms; the "What it decides" form table gains a row "Logic, control flow, structure, or a delta over code | A code-shape sketch (pseudocode, call tree, component or file tree, types, diff)"; the "not a comprehension aid" paragraph is untouched; line 3 "One skill, one job" untouched.
2. `plugins/visualization/CHANGELOG.md`: new `## [0.5.0]` above `## [0.4.2]` with `### Added` (the code-shape family and heuristic, the `context/code-shapes.md` spoke, the thin-context menu, the terminal-only rule, the new trigger, evals 8-12; cites `docs/upstream/humanlayer-skills.md`) and `### Fixed` (the three CSP sentences, the dead citation, the version-specific mermaid runtime record, the public-sharing entry). The `### Added` entry closes with a short "Notice" paragraph carrying `Copyright (c) 2026 HumanLayer` and the MIT permission notice verbatim, introduced by one sentence saying the paragraph travels with the example blocks in `skills/visualize/context/code-shapes.md` and must survive any future changelog trim. This is the shipped carrier of the notice; the skill and its spokes carry none.
3. `plugins/visualization/.claude-plugin/plugin.json`: `version` 0.5.0; add "code-shape sketches" to the form list in `description` so the catalog row matches the skill; add `userConfig.thin_context_prompt` (type string, title "Prompt on a bare code paste", default `auto`, description naming the three values and the unrecognized-value fallback, in the same shape as `medium`).
4. Regenerate: `node scripts/generate-catalog.mjs` (description changed), `node scripts/generate-cheatsheet.mjs` (no-op expected; run `--check`), and `python3 scripts/sync-plugin-options-docs.py` (new option; the README block is fenced `ai-slop-ignore` because the generator emits em dashes). Extend the README's hand-written Configuration section with the new option in the `medium` paragraph's shape.

- **Sanity Check:** `grep -c '"version": "0.5.0"' plugins/visualization/.claude-plugin/plugin.json` returns 1 and `grep -c '"thin_context_prompt"' plugins/visualization/.claude-plugin/plugin.json` returns 1
- **Sanity Check:** `python3 scripts/sync-plugin-options-docs.py --check` exits 0 and `grep -c "CLAUDE_PLUGIN_OPTION_THIN_CONTEXT_PROMPT" plugins/visualization/README.md` ≥ 1
- **Sanity Check:** `bash scripts/check-changelog-parity.sh --check-preserved origin/main` exits 0 (about 16 s here); `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0 as a background run with a ceiling above 1300 s (it took 1248 s on this Windows Git Bash box), or is deferred to CI with that stated in the PR body
- **Sanity Check:** `node scripts/generate-catalog.mjs --check` exits 0 and `node scripts/generate-cheatsheet.mjs --check` exits 0
- **Sanity Check:** `bash scripts/check-skill-count-claims.sh --check` exits 0
- **Sanity Check:** `grep -c "code-shape" plugins/visualization/README.md` ≥ 2
- **Sanity Check:** `grep -c "Copyright (c) 2026 HumanLayer" plugins/visualization/CHANGELOG.md` returns 1 and `grep -c "Permission is hereby granted" plugins/visualization/CHANGELOG.md` returns 1

### Phase 7: Gate sweep, manual eval pass, and commit [DONE]

Run every gate the change touches, the provenance proof, a local markdownlint pass, and a manual eval pass, then commit on `feat/visualize-absorb-show-me` with a Conventional Commit; push and PR only on the user's go.

Manual eval pass (nothing in the repo executes evals): in a fresh session with the edited plugin loaded, run the prompts of evals 1, 2, 3, 4, 8, 9, 10, 11, 12 and record pass/fail per expectation in the PR's Verification section; use `claude plugin eval` instead if it is enabled for this account. Evals 1-3 are the regression guards for the new rows and the menu rule.

- **Sanity Check:** `bash scripts/check-purged-em-dashes.sh` exits 0
- **Sanity Check:** `! grep -rqiE "humanlayer|show-me|horthy|license|adapted from|inspired" plugins/visualization/skills plugins/visualization/README.md && ! grep -rqw "MIT" plugins/visualization/skills plugins/visualization/README.md` exits 0
- **Sanity Check:** `npm ci` then `npx markdownlint-cli2 plugins/visualization/skills/visualize/SKILL.md plugins/visualization/skills/visualize/context/code-shapes.md plugins/visualization/skills/visualize/context/decision-matrix.md plugins/visualization/README.md plugins/visualization/CHANGELOG.md docs/upstream/humanlayer-skills.md` exits 0
- **Sanity Check:** `bash scripts/check-changed-skills.sh origin/main` exits 0 (background run, 540 s ceiling)
- **Sanity Check:** `bash scripts/affected-tests.sh --run` exits 0 (background run; the evals.json edit over-selects ~148 suites, budget tens of minutes, or lean on CI and say so in the PR body)
- **Sanity Check:** the PR's Verification section lists a verdict for each of evals 1, 2, 3, 4, 8, 9, 10, 11, 12
- **Sanity Check:** `git log --oneline origin/main..HEAD | grep -c "feat(visualization)"` ≥ 1 and `git status --short` prints nothing. `docs/topics/visualize-absorb-show-me/` (PLAN.md and `design/`) is committed on the branch as the contract tier and pruned at `/planning:plan close-out` before merge; `.work/` (the interview and plan ledgers, EXPLORE.md, RESEARCH.md) is gitignored and machine-local, so a fresh clone resumes from PLAN.md alone

### Files Affected

| File | Action | What changes |
|---|---|---|
| `plugins/visualization/skills/visualize/context/code-shapes.md` | Create | seven form sections with examples plus "Selecting a view" |
| `plugins/visualization/skills/visualize/evals/evals.json` | Modify | cases 8-12; eval 4 expectation 3 reworded |
| `plugins/visualization/skills/visualize/SKILL.md` | Modify | description, Step 1, Step 2 rows and heuristic, Step 3 sentence, Step 4 thin-context branch, NOT-do bullet |
| `plugins/visualization/skills/visualize/context/decision-matrix.md` | Modify | CSP sentence, code-shape entry, citation swap, two UNVERIFIED records |
| `docs/upstream/humanlayer-skills.md` | Create | provenance record with coverage table and license notice |
| `docs/conventions/upstream-drift/README.md` | Keep | Adopters table does not list cursor-pstack (verified); no row added |
| `plugins/visualization/README.md` | Modify | skill row and form table |
| `plugins/visualization/CHANGELOG.md` | Modify | `## [0.5.0]` |
| `plugins/visualization/.claude-plugin/plugin.json` | Modify | version, description phrase |
| `docs/CATALOG.md` | Regenerate | visualization row |

### Dependencies

- Phase 3 cites `context/code-shapes.md` (Phase 1) and is graded by the evals (Phase 2). Phase 6 describes Phases 1-5. Phase 7 runs after 6.
- Downstream consumer: `education:teach`'s pedagogy spoke routes concept diagrams to `/visualization:visualize`; the mermaid rows and the description's first clause are unchanged, so that routing is unaffected.

### Alternatives Considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Wrap the upstream plugin (eli5 shape) | 100 lines of text with no runtime; a delegation address to babysit for no behavior we cannot carry | upstream ships tooling or a renderer the text cannot carry |
| New sibling skill | triggers collide with `visualize`; a permanent listing line on an over-budget aggregate; breaks "One skill, one job" | the listing budget rises, or the code-shape triggers diverge from visualize's in practice |
| Examples inline in SKILL.md | ~300 lines, rows become a wall | the spoke goes uncited or unread in eval runs |
| Reauthor every example | no benefit once attribution is externalized; the user chose verbatim-where-it-works | a legal review requires no verbatim carry |
| Separate PR for the catalog fixes | second branch and PR cycle for four sentences in the same file | the fixes are contested in review and would block the feature |

### Test Strategy

The plugin has no executable tests; its contract is the evals set plus the repo gates. Test boundaries, all existing: `check-skill.sh` (25 static checks incl. trigger preservation), the evals JSON schema step, `check-evals-quality.sh`, `check-changelog-parity.sh`, `generate-catalog.mjs --check`, `check-purged-em-dashes.sh`, `check-skill-count-claims.sh`. No new boundary is introduced. Red first: Phase 2 writes evals 8-12 before Phase 3 changes the body; Phase 3 is green when the body satisfies them (graded by the Phase 7 manual pass, since nothing in the repo executes evals) and `check-skill.sh` reports 0 errors. Edge cases covered by the evals: delta over a known shape (9), restraint on a small question (10), thin-context code paste with several fitting forms (11), terminal-only under an explicit `artifact` argument (12). Existing evals 1-3 are the regression guards; eval 4's third expectation is reworded; evals 5-7 are unchanged; all must still pass the quality lint.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Description cannot fit the new phrase and trigger under 1024 | Med | Low | trim the closing clause per Phase 3.1; if still over, accept the 2b WARN (briefed) and state it in the PR body; never exceed 1536 |
| Provenance leaks via a carried sentence ("Help the user understand…", "show-me-{description}.html") | Med | High | Phase 1 and 3 grep proofs; the upstream HTML filename pattern and the "help the user understand" framing are not carried |
| Em dashes ride in with verbatim upstream text | High | Low | Phase 1 and 7 grep proofs; the purge gate on SKILL.md and README |
| New rows overlap the mermaid row (flow, hierarchy, state) and eval 1 regresses | Med | Med | rows worded by content origin plus the code-vs-domain tie-break; eval 1 named as the regression guard in the PR |
| Thin-context menu fires on every paste and regresses evals 2 and 3 | Med | Med | the menu is conditioned on two or more code-shape forms fitting about equally; one dominant form renders; evals 2, 3, 10, 11 grade both sides in the manual pass |
| Pseudocode row reads as a comprehension digest of pasted code (teach-row precedent) | Med | Med | row restricted to prose-described or not-yet-written logic; eval 11 expects no paraphrase |
| The MIT notice in the CHANGELOG is trimmed away in a future release | Low | Med | the entry states it must survive trims; the docs/upstream record is the second carrier |
| Nothing executes the evals, so regression claims rest on unrun cases | High | Med | Phase 7 manual eval pass with recorded verdicts in the PR; `claude plugin eval` if enabled |
| `check-skill.sh` exceeds the foreground timeout locally | High | Low | run in the background with a 540 s ceiling (verified this session) |
| CATALOG.md regeneration drifts other rows | Low | Low | `generate-catalog.mjs --check` at base is clean; diff only the visualization row |

## Blast radius

MEDIUM. Ten files in one plugin plus two repo docs, all markdown or JSON, fully revertible with `git revert`. Automated gates cover every touched surface. The change edits agent instructions for one skill (not fleet-wide), so the "new agent-instruction rules" trigger applies at skill scope. Stress-test: yes, `/planning:devils-advocate` dispatched to a fresh context (Step 4).

## Stress-test summary

**Step 4, `/planning:devils-advocate` in a fresh context (2026-09-04):** 0 CRITICAL, 7 HIGH, 7 MEDIUM, 8 LOW. Every HIGH was verified against the files by the parent and applied:

| Finding | Disposition |
|---|---|
| H1 new rows overlap the mermaid row; eval 1 regresses | rows reworded by content origin; code-vs-domain tie-break added (Phase 3.3) |
| H2 thin-context branch fires on thinness alone; evals 2, 3 regress | menu conditioned on two or more code-shape forms fitting about equally; folded into the existing form-ambiguity bullet (Phase 3.5) |
| H3 pseudocode row is a comprehension digest of pasted code | row restricted to prose-described or not-yet-written logic; eval 11 expectation added (Phase 3.3, Phase 2) |
| H4 CSP fix leaves lines 102 and 182 contradicting it | all three sites rewritten; "inline everything" restated as plugin policy (Phase 4.1) |
| H5 MIT notice in docs/upstream never ships with the plugin | notice also carried in the shipped `## [0.5.0]` CHANGELOG entry; Brief amended (Phase 6.2) |
| H6 "repository-authored" is not a trust boundary; precedence over rung 1 unstated; no eval | first fixed as blanket terminal-only; then refined by user direction to the baseline's own content class (PR diff, fetched content, another repository's files) pinned to the terminal with stated precedence and a notice, while code-shape forms otherwise keep the ladder and the `medium` choice; eval 12 added; Brief amended (Phase 3.4, 3.6, Phase 2) |
| H7 the file-layout diff contains `show-me.ts`; verbatim carry is impossible under the grep proof | that diff, the `expandSkillMention` line, and the `expandSkill` block are adapted with neutral identifiers; the other blocks stay verbatim; recorded per block in the attribution table (Phase 1, Phase 5) |
| M1 description edit measured 1026 | trim retargeted, measured at exactly 1024 (Phase 3.1) |
| M2 mermaid record's per-release trigger already fired (v2.1.260 shipped; value held) | stamp at commit time against the installed binary; triggers changed to serviced events (Phase 4.4) |
| M3 #79824 has drifted to a content-type catch-all | entry reworded with the three reported content types and #81410 (Phase 4.5) |
| M4 markdownlint never runs locally | `npm ci` + `npx markdownlint-cli2` on touched files (Phase 7) |
| M5 ~30 lines of standing instruction with no stumble evidence | PR body names the evidence (Phase 3 note) |
| M6 "Red then Green" has no executor | manual eval pass with recorded verdicts; `claude plugin eval` if enabled (Phase 7) |
| M7 Step 1 pre-selects a form | Step 1 reads the target only; the delta anchor lives in the Step 2 row (Phase 3.2) |
| L1-L8 | `grep -w MIT` case-sensitive; `! grep -q` forms; `PYTHONUTF8=1` and `encoding='utf-8'`; `narration: true` on prose-path evals; recheck trigger on "Not audited"; affected-tests in the background; whole block presented as the fallback; fire-icon bullet reworded |

**Step 3, fresh-context plan reviewer (2026-09-04, against the revised plan):** 0 CRITICAL, 6 IMPORTANT, 7 SUGGESTION. Each verified by the parent against the files and applied:

| Finding | Disposition |
|---|---|
| 1 two more stale CSP sites (lines 35-36, 198) | added to Phase 4.1; sanity greps extended |
| 2 "version is undocumented" at lines 70 and 91; verified record filed under UNVERIFIED | reworded; record moved to the Published Artifact section (Phase 4.4) |
| 3 Brief's Untouchable bullet and Goal sentence contradict the terminal-only rule; NOT-do bullet narrows the rich-page path | Brief amended; NOT-do bullet scoped to code-shape forms so no `### Changed` is owed |
| 4 `check-changelog-parity.sh --check-bump` takes ~1250 s here | marked background with a ceiling above 1300 s, or deferred to CI (Phase 6) |
| 5 coverage enumeration double-counted and under-counted; grep counted lines | twenty enumerated rows; sanity check counts table rows (Phase 5) |
| 6 eval 4 expectation 3 contradicts eval 11 | expectation reworded (Phase 2) |
| 7 scope numbers drift (8-11 vs 8-12, "four cases") | aligned to 8-12 everywhere |
| 8 Phase 1 said both drop and rename `expandSkillMention`; example paths read as ghost refs | rename only; spoke opens with a "paths and identifiers are placeholders" line |
| 9 pin: upstream HEAD is 3c26291, the file's last change 6ab9013; v1.0.1 is the manifest version | record both; recheck against 6ab9013 (Phase 5) |
| 10 absence claim named "the docs corpus"; #52517 misdescribed | the two pages and the llms-full sweep named; #52517 described as Desktop's Claude Code tab (Phase 4.3) |
| 11 `$(command -v claude)` may be a shim | `readlink -f` and a size check first (Phase 4.4) |
| 12 contract-slice commit status unstated | stated: docs/topics committed on the branch, `.work/` machine-local (Phase 7) |
| 13 "fit about equally" grep collides with existing text | anchored on "two to four" (Phase 3) |

Verified with no finding by the reviewer: the `check-skill.sh` invocation form and env vars; `check-evals-quality.sh` takes a file path; `--check-bump`/`--check-preserved` exist; check 5 scans only SKILL.md; check 15 is per-directory; the new rows add no HTML lane, so the 40-line cap and the security baseline hold; the cheat sheet reads only `workflow-stage`/`summary`, so the description edit is a no-op there; `package-lock.json` pins markdownlint-cli2 0.23.2 so `npm ci` works; catalog `--check`, count-claims, evals-quality and jsonschema are green at base.

## Execution shape

Fully sequential in the main session: 1 → 2 → 3 → 4 → 5 → 6 → 7. Phases 1, 2, 4, 5 are file-disjoint and could run as parallel sub-agent workers, but the independent volume is ~150 lines of markdown with strict no-provenance and glyph constraints, so the token cost of parallel workers is not worth the saving. [EXEC-SHAPE]

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | verbatim-carry judgment and house-style rewriting |
| 2 | main-session | five JSON cases and one reworded expectation, tightly tied to Phase 3 wording |
| 3 | main-session | description trim under a codepoint cap; wording judgment |
| 4 | main-session (worker-eligible) | five targeted edits with exact anchors |
| 5 | main-session (worker-eligible) | mechanical given the coverage table |
| 6 | main-session | CHANGELOG describes all prior phases |
| 7 | main-session | gates and commit |

Sequential fallback: not applicable (already sequential). If the user asks for speed, Phases 4 and 5 can be dispatched as two workers with ALLOWED = their single file each and FORBIDDEN = everything else, then Phase 6 waits for both.

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] Sequential main-session execution, evals before body | Phase order 1-7; no parallel workers; Execution shape section | ~150 independent markdown lines under strict no-provenance and glyph constraints; parallel token cost outweighs the saving (plan-template threshold ≈100 LOC) |
| [EXEC-SHAPE] `plugin.json` description gains "code-shape sketches"; `docs/CATALOG.md` regenerated | Phase 6.3-6.4 | `docs/CATALOG.md` row 109 is generated from the manifest description; `generate-catalog.mjs --check` is a CI gate |
| [EXEC-SHAPE] No Adopters row in the upstream-drift convention | Phase 5, Files Affected | `docs/conventions/upstream-drift/README.md` lists no `cursor-pstack.md` row (grep, 2026-09-04) |
| [EXEC-SHAPE] Description trim targets the closing "Not for…" clause, ending "(a dataviz capability owns it)" | Phase 3.1 | measured at exactly 1024 codepoints this session; the ten quoted triggers and first clause untouched |
| [EXEC-SHAPE] Security sentence lands in Step 3 and as a NOT-do bullet, not a Gotcha | Phase 3.4, 3.6 | Step 3 owns medium selection; Gotchas in this skill are observed pitfalls, not rules |
| [EXEC-SHAPE] Three upstream blocks adapted (file-layout diff, `expandSkillMention` line, `expandSkill` function); a "placeholders" line opens the spoke | Phase 1, Phase 5 table | upstream line 76 contains `show-me.ts`; the other two describe implementing the upstream command; repo audit-noise standard on ghost paths |
| Code-shape forms ride the existing ladder; only PR diffs, fetched content, and other repositories' files are pinned to the terminal until the escape helper ships (user-directed, replaces the earlier blanket terminal-only fallback) | Brief constraint; Phase 3.4, 3.6; eval 12 | rendered-views security baseline names exactly that content class; the `medium` option already carries user choice; user direction 2026-09-04 to keep choice and prescribed defaults |
| `thin_context_prompt` option (`auto`/`always`/`never`, default `auto`) governs the ranked-menu behavior (user-directed) | Brief constraint; Phase 3.5, 6.3-6.4 | user direction to route defaults through plugin options; `medium` is the in-repo shape for a trivial scalar option |
| Upstream HTML bullet merged into the rich-page row and Step 5 rather than marked "not taken" (user-directed) | Phase 3.7, Phase 5 table | user direction to merge what integrates; upstream text lines 117-120 |
| MIT notice carried in the shipped CHANGELOG 0.5.0 entry as well as docs/upstream (confirmed by the user's "proceed") | Brief constraint; Phase 6.2 | installed plugin cache holds only `.claude-plugin/`, `CHANGELOG.md`, `README.md`, `skills/`; docs/upstream never ships |

## Open questions

None at approval time. Q1-Q13 are answered in the interview ledger; the two [FALLBACK] rows above are the only items that reshape an interview answer and are gated for confirmation.

## Handoff to implementation

### User-approval gates

- Resolved 2026-09-04 by user direction: code-shape forms keep the existing ladder and user choice; only the baseline's content class is pinned to the terminal; `thin_context_prompt` added; upstream HTML specifics merged; the CHANGELOG carries the notice. No open gates remain besides the two below.
- Push and PR creation (never automatic).
- If the implementer's codepoint count for the Phase 3.1 description differs from the measured 1024, confirm accepting the 2b WARN before landing.
- Any carried upstream sentence that would need the "help the user understand" framing to make sense: stop and rephrase rather than carry it.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential main-session execution, order 1-7 (evals before body).
- [EXEC-SHAPE] `plugin.json` description gains "code-shape sketches" and `docs/CATALOG.md` is regenerated, so the catalog row matches the skill.
- [EXEC-SHAPE] Adopters row in `docs/conventions/upstream-drift/README.md` only if that table already lists `cursor-pstack.md`.
- [EXEC-SHAPE] The Phase 3.1 trim targets the description's closing "Not for…" clause; the ten quoted triggers and the first clause are untouched.
- [EXEC-SHAPE] The security sentence lands in Step 3 (medium) and as a NOT-do bullet, not as a Gotcha.

### Mechanical work

- Commit at the end of Phase 7 as `feat(visualization): absorb code-shape sketch forms into visualize (0.5.0)` with the repo's Co-Authored-By trailer. The contract slice `docs/topics/visualize-absorb-show-me/` rides the branch and is pruned at `/planning:plan close-out` before merge.
- Verification checkpoints: Phase 2 (evals schema + quality), Phase 3 (check-skill background run), Phase 6 (parity, catalog, count claims), Phase 7 (full sweep).
- PR body per `.claude/rules/pr-body-contract.md`: opens with `No related issue: absorbing an upstream skill decided in-session`, then Summary / Fix / Verification / Related (link the upstream record and pin).
