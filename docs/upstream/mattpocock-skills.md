# Upstream source: mattpocock/skills

This page records what this marketplace took from, or decided against, in
[mattpocock/skills](https://github.com/mattpocock/skills) by Matt Pocock (MIT license). Credit for
that work lives here and in plugin CHANGELOGs, never in skill bodies. A citation an agent uses
while working, such as the Fowler smell baseline in `review`, is content rather than credit and
stays where it is.

The companion page for the other upstream skill collection we adapt is
[`cursor-pstack.md`](cursor-pstack.md) (cursor/plugins, pstack); it records where a pstack unit
conflicts with a skill derived from this repository. Rows below link upstream at the pinned commit
and hold our decisions only, in our words; read upstream at the link for what it says.

**Last audited upstream state:** `mattpocock/skills@d81f3a183412e71a5b1e84ca21bc1a35eea03a60` under `skills/` (the v1.3 content, 37 skills, audited 2026-10-04 in the `pocock-upstream-sync` topic; the previous pin was `84fdeffd12f2ee307994d1eb6feb48173b6e0502`, v1.2.3). Upstream tagged v1.3.0 and v1.3.1 after this commit; the only change past the pin in those releases is upstream PR [#1121](https://github.com/mattpocock/skills/pull/1121), read and recorded in the `diagnosing-bugs` row.

**Recheck trigger:** a change, between the pinned commit and upstream HEAD, to a path a row we took
or rejected something from links, a unit removed or added under the scope: re-audit the affected
rows. `scripts/check-upstream-drift.sh` detects these, and the monthly drift issue for this
upstream lists them ([upstream-drift convention, "Pinned git upstreams"](../conventions/upstream-drift/README.md#pinned-git-upstreams)).
Re-auditing moves the pin and records the outcome per row.

## Attribution table

| Upstream (links at the pin) | Ours | Relation | Decision |
|---|---|---|---|
| [`to-questionnaire`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/to-questionnaire) (graduated in v1.2.0, [#593](https://github.com/mattpocock/skills/pull/593)) | `planning:questionnaire` | Derived | Kept: the interview covers only how the questionnaire is sent, never its subject. Changed: output goes to the memory slice instead of the working directory (it can hold personal data), interview vocabulary replaces grilling, and a tracker-item option exists. Re-audited at v1.2.3 with nothing to take: upstream's one template change there is already in ours, and ours adds route-away, an overwrite guard and multi-recipient role slugs. Re-audited at the pin (2026-10-04): upstream behavior unchanged. Not taken: upstream's worked question example; our `templates/questionnaire.md` holds placeholders only. Deliberate divergence: upstream is user-invoked, ours is model-invoked since the re-grade ([#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969)) |
| [`wayfinder`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/wayfinder) | `planning:wayfind` | Partial | Taken: the fog-of-war framing and the test that tells a sharp ticket from fog. Rejected: a file-based map (we use native tracker items) and upstream's tracker seam. v1.2 re-audit: adopted the parallel research burn-down (a work-mode exception plus a chart-mode offer) and the bail-out when a chart finds no fog; the decision-ticket idea already existed as our decision item; rejected the `research/<name>` branch, which the two-lane branch-naming rule forbids (resolution comments and the memory tier hold findings); the hand-off when the map clears was already present with named graduation targets. Course lane W (#2939): C18 adopted (narration names an item by title, with the number as link or suffix; `wayfind` only); C19 adopted (Out-of-scope holds scope decisions, never fog; a wrongly scoped item is closed with one linking line); C20 already present (each decision lives in its own item; the map summarizes and links). Upstream failure reports open on 2026-10-04, none acted on: [#576](https://github.com/mattpocock/skills/issues/576), [#828](https://github.com/mattpocock/skills/issues/828) and [#944](https://github.com/mattpocock/skills/issues/944); [#530](https://github.com/mattpocock/skills/issues/530) is the `research` report behind the parallel burn-down |
| `batch-grill-me` rounds, now [`grill-me`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/grill-me) and [`grilling`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/grilling) | `planning:interview`, carried into `prd`, `design` and `plan` | Derived (behavior) | Taken: questions asked in rounds, facts kept apart from decisions, and a confirmation gate. Ours adds a vocabulary rule (no "grill") and subagents that gather facts in the background. v1.2 re-audit: adopted the question and answer emoji markers as an opt-in `userConfig` key (`use_emoji_question_markers`, default off); answering by number and in any order was already present; rejected the one-question-at-a-time opt-out line, because it belongs in the consumer's own CLAUDE.md and the plugin has nothing to ship for it |
| Grilling-family rework ([upstream PR #532](https://github.com/mattpocock/skills/pull/532)), now in [`domain-modeling`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/domain-modeling) and [`grill-with-docs`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/grill-with-docs) | `planning:interview`, `architecture:improve` | Partial | Taken: the decision-tree rename, routing by domain, and the line between a primitive and a variant. The ADR three-gate test and the glossary purity rule were once recorded as our own additions. A 2026-08-18 audit (two independent validators) found both in upstream `domain-modeling`; which came first could not be checked then, so treat them as convergent or derived, not as ours alone |
| [`git-guardrails-claude-code`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/misc/git-guardrails-claude-code) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Taken: the capability, a hook that stops destructive git commands. Rejected: the substring-matching implementation, which blocks safe commands; ours parses the argv grammar instead |
| [Upstream PR #464](https://github.com/mattpocock/skills/pull/464) (review checklist) | `review` code-reviewer Fowler baseline | Pointer | The PR suggested the idea; the content was rebuilt from Fowler, *Refactoring*, 2nd ed., ch. 3, with no upstream wording |
| [`code-review`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/code-review) (course flow skill, separate from PR #464) | `review`: `quality-gate` lenses, `fanout`, code-reviewer agent | Partial | Course lane D (#2937): C12 adopted with corrections (spec conformance became a ninth `quality-gate` lens, with `context/spec.md` owning the missing, scope-creep and wrong outcomes; branch-scoped, and the container-scoped case was later filled by the close-out lens); C13 already present plus one edit (`fanout` already shows two axes separately; the proposed never-merge, never-rerank rule was withdrawn because it negates the normalization `fanout` exists to run; `axis` versus `lens` vocabulary recorded once in `review/context/severity.md`); C14 adopted with corrections (a spec-source discovery ladder with bare `#N` validation and promotion, a provider-mechanic read, and a topic-slug rung); C15 partial (a fail-fast preflight, scoped by mode with `allowed-tools` widened; `fanout`'s untracked-only stop deliberately not copied); C16 already present (both suppression halves are in `code-reviewer.md`) |
| Handoff failure reports ([#186](https://github.com/mattpocock/skills/issues/186), [#306](https://github.com/mattpocock/skills/issues/306), [#617](https://github.com/mattpocock/skills/issues/617), [#482](https://github.com/mattpocock/skills/issues/482)) against [`handoff`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/handoff) | `session-flow` handoff claim-provenance and constraint re-scan rules | Derived (failure corpus) | Two rules adopted from the incident threads; the rest rejected (verdicts on issue #1477) |
| [`triage`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/triage), including its out-of-scope ledger ([`OUT-OF-SCOPE.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/triage/OUT-OF-SCOPE.md)) | `work-items:triage` | Derived (structured port) | Our rejected-concept ledger (work-items 0.6.0: the ledger check plus the won't-fix and already-implemented outcomes) is a structured port of upstream's out-of-scope ledger: one file per concept, matching by meaning rather than keyword, and no ledger entries for built features. Ours is a superset. Our rule that a PR enters triage like an issue, and the state-machine framing, converge with upstream. The v1.2 adoption candidate for the ledger (M15) was rejected as already adopted; record corrected in lane 5, with no behavior change. Copy check 2026-10-04 (`/attribution:audit`): wording was rewritten. A later redesign the same day gave the needs-info comment a layout of our own (a paused header and where triage stopped, then the questions, each naming what its answer decides, then what the pass settled), which closes the copy question for that comment; no script or test read the old headings. On 2026-10-04 the three attention-view buckets became a table keyed to what each item is waiting for, and `reference/agent-brief.md` (from upstream's [`AGENT-BRIEF.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/triage/AGENT-BRIEF.md)) replaced its four principles with per-field rules under names of our own; the template's sections and its `## Agent Brief` heading are unchanged |
| [`to-spec`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/to-spec) | `planning:plan` and `planning:prd` Brief, `work-items:decompose` container lifecycle | Partial | Course lane A (#2934): C1 already present (`planning:interview` synthesizes directly when intent is clear; `plan` with no argument finalizes without a new interview); C2 partial, routed to lane C (#2936: a sketch of the test boundary before the spec, beside C9; the claim that one seam is ideal rejected as folklore); C3 partial (an optional `## Testing decisions` section with pointers to existing tests; the demand for very long numbered lists stays excluded); C4 adopted with a gate added (the spec publishes to the tracker as a `work-map` container with slices as native sub-items; upstream's publish without a gate excluded). Archiving specs adopted as archival by closing the container |
| [`to-tickets`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/to-tickets) | `work-items:decompose` | Partial | The vertical-slice and tracer-bullet vocabulary overlaps upstream and the seam plumbing is ours. Lane B (#2935) adopted four mechanics: a prefactor slice as a blocker (C5), sizing to one fresh context window (C6), the integration-branch fallback (C7) and the PR-variant agent brief (C17); C8, working the frontier, is vocabulary only. Lane B verdicts: C5, C6, C7, C8 and C17 adopted. Copy check 2026-10-04 (`/attribution:audit`): wording was rewritten. A later redesign the same day restructured the slice rules (four ordered checks in a table, prefactor slices first), expand-migrate-contract (an item table with its blockers) and the slice body (Parent, Depends on, Outcome, Done when), which closes the copy question for those parts. Pending: step 3's approval fields and questions still follow upstream's structure |
| [`tdd`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/tdd) (with its `tests.md` and `mocking.md`) | `planning:plan` Test strategy, `tdd:principles`, `testing:write`, `review` code-reviewer | Partial | Course lane C (#2936): C9 partial, relocated (agreeing test boundaries before writing tests lands in `plan`'s Test strategy element, deliberately not called "seam" and not hosted by `implementation:phase-verifier`; upstream's hard consent gate softened to a `DEVIATIONS.md` record an unattended run can satisfy); C10 already present (the tautological-test anti-pattern in `anti-patterns-khorikov.md` and `testing/write`; the executable half landed as a `code-reviewer.md` criterion, `review` 0.24.0, which defers to `cant-fail-scan.sh` when that scan's output is in context); C11 already present plus one clause (`test-doubles.md` has preferred typed client interfaces to a generic fetch wrapper since `85aa8066`; added only that the shape rule never widens what gets mocked). A zero-assembly chain document rejected, with reasons: the draft chain was wrong |
| [`improve-codebase-architecture`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/improve-codebase-architecture) scoping filter (v1.2, [#533](https://github.com/mattpocock/skills/pull/533)) | `architecture:improve` deepening Phase 1 | Partial | Adopted scoping before scanning: a direction the user names limits the scan; with none, recent-commit hot spots come first (precomputed context widened to 20 commits). Rejected upstream's fixed context file (we use our glossary-discovery ladder) and the HTML report's CDN scripts and Mermaid (rejected earlier; its card and diagram layout was taken and is restated in our own words, see the map line). Corrected 2026-10-04: no grilling integration was ever taken; the deepening interview runs its own loop and calls only `curate-language`. Upstream's glossary file is `GLOSSARY.md` from v1.3 (was `CONTEXT.md`); the rejection stands. v1.3 removed the inbound hand-off from `diagnosing-bugs` (`1dab982`); nothing to change here |
| [`codebase-design`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/codebase-design) (with its `DEEPENING.md` and `DESIGN-IT-TWICE.md`) | `architecture:improve` deepening | Derived | Corrected 2026-10-04 from convergent: the vocabulary was ported close to verbatim when the plugin was added (`30cf0343f`, 2026-07-10). Taken: the module-design vocabulary and its rejected framings, the four dependency categories, the two-adapter and internal-seam rules, replacing shallow-module tests rather than layering new ones, and the Design-It-Twice fan-out (framing first, orthogonal design constraints, a structured return per design, comparison on depth, locality and seam placement, an opinionated pick). From another source: the sixth return part for rejected shapes, reading the spread of returns as evidence, and the graft record for a hybrid come from pstack `arena` (see [`cursor-pstack.md`](cursor-pstack.md)). Ours: grounding a consequential winner outside the repository, and the scan briefing's badge-acceptance heuristics. Not taken: the fixed context file (we use our glossary-discovery ladder) and the testability code examples. Copy check 2026-10-04: restated in our own words, `vocabulary.md`, `interface-design.md` and `scan-briefing.md` around a tax-calculation example and `dependencies.md` around mail and shipping-rate examples; the only shared five-word runs left are labels other files cite (a return-part name and the category values). Upstream issues [#449](https://github.com/mattpocock/skills/issues/449) and [#458](https://github.com/mattpocock/skills/issues/458), open on 2026-10-04, ask how to apply it; none acted on |
| [`diagnosing-bugs`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/diagnosing-bugs) (v1.2.3 redaction and tagged logs) | `debugging:debug`, `testing:diagnose` | Partial | Adopted the redaction guard in both skills (secrets replaced with `<REDACTED>` in any shown command, output or artifact; credentials in environment variables covered; only signal lines quoted) and the `[DEBUG-a4f2]` tagged-log convention in `testing:diagnose` (already in `debugging:debug`). `debugging:debug` also carries the feedback-loop-first doctrine: a loop gate before any hypothesis, ten loop kinds ranked by preference, 3-5 ranked falsifiable hypotheses, the correct-seam rule for the regression test, and a human-run loop template. On 2026-10-04 these were restated in our own structure (one running example through every phase, the loop kinds and the seam rule as tables, a grouped cleanup checklist) and the template was rewritten. Upstream's separate minimise step and its Phase 1 completion checklist were first judged covered by our phase gates; the re-evaluation at the pin (2026-10-04) reopened both as gaps under evaluation, since our regression-test step refers to a minimized repro that no phase produces. Upstream removed its post-mortem hand-off in `1dab982` (upstream PR #880): kept ours, because our post-mortem phase files the finding and calls no skill. Past the pin, upstream PR #1121 (v1.3.1) routes the post-bug reflection to `retro`; recorded, nothing taken |
| [`wait-what`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/wait-what) (new in v1.2, [#751](https://github.com/mattpocock/skills/pull/751)) | `discipline:wait-what` | Derived | Ported as a declared non-corrector in `discipline`, beside `tighten-your-output` and `mind-your-maxims`; the home follows who is at fault (the model's output drifted, not the reader's comprehension). The name is kept under a PLUGIN-PHILOSOPHY naming exception (the utterance is the mechanism, and users know the upstream name); a naming tournament's winner, `re-pitch`, was declined by the user. Rejected upstream's fixed glossary file names (`CONTEXT.md` at v1.2.3, `GLOSSARY.md` and `GLOSSARY-MAP.md` from v1.3, `006a52b`, with no fallback for the old names; open upstream issue [#1153](https://github.com/mattpocock/skills/issues/1153)): we find the nearest glossary or context map by the consumer's convention and use plain technical English without one. Upstream's v1.3 map-following now matches ours, so the rejection covers only the fixed names. Kept user-invoked, on the evidence of the author's X thread (statuses 2084753070437609606, 2084941367659168064 and 2085681281795232026), which compares a standing instruction, an output style and an on-demand skill for this job. Copy check 2026-10-04 (`/attribution:audit`): the description and opening instruction were rewritten; the panel splits on whether the three-part instruction still follows upstream, so the question is open for a person |
| [`wizard`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/wizard) (graduated in v1.2) | `wizard:generate` | Derived | Ported in lane 4 as the single-capability plugin `wizard` 0.1.0, hardened. Kept: the process (scope from the repo, a concrete path per stage, authoring onto the template, static verification), regrouped as three phases around one stage-plan table, a fixed, never hand-edited library section ahead of the `STAGES` marker, model invocation with an explicit non-trigger fence, degrading when `gh` is absent, ephemeral output by default, and the agent writing but never running the script. Hardened (deltas in `plugins/wizard/CHANGELOG.md` 0.1.0): a human reads and approves the whole STAGES block before `chmod +x`; `open_url` accepts https only (also closing a Windows UNC/NTLM leak through explorer.exe); prompts read `/dev/tty` and fail closed; `.env` writes are quoted, mode `0600`, gitignore-asserted and atomic; `gh` writes name a confirmed `--repo` and refuse empty values; key names are validated; readline on non-secret prompts (upstream [#741](https://github.com/mattpocock/skills/issues/741) where safe); live `.env` scoping reads names only. Rejected: the Codex `agents/openai.yaml` sidecar (see the Codex finding under Harness findings). Upstream status 2026-10-04: the template dropped its time-remaining display in v1.2.3 while its docs page still shows it; a later sync keeps it out. Open upstream bugs [#1041](https://github.com/mattpocock/skills/issues/1041) (`write_env` leaves the shell variable unset) and [#811](https://github.com/mattpocock/skills/issues/811) (a symlinked `.env` is replaced) reproduced in our `template.sh` and were fixed here by #6275 (a symlinked `.env` is written through, not atomically); [#1142](https://github.com/mattpocock/skills/issues/1142) (editing the script mid-run) is unassessed |
| [`prototype`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/prototype) HTML demo shell (v1.2) | `prototype:pressure-test` | Partial | Adopted in lane 5 (prototype 0.5.0): the terminal app stays the default; when the person driving it is not a developer, or no terminal fits, the throwaway shell over the same pure logic module is one self-contained `file://` page with domain labels, a state panel redrawn on each click, free-play buttons and guided scenarios that reset to a known start, under explore-directions' HTML constraints (restrictive CSP meta tag, a `mktemp -d` or `%LOCALAPPDATA%\Temp` location, synthetic data only, deleted after the markdown capture). Rejected: keeping the prototype runnable on a throwaway branch as the primary record, which breaks the two-lane branch-naming rule and the plugin's delete-when-done rule (`plugins/prototype/context/discipline.md`, "Delete or absorb when done") |
| `ask-matt` [`PHASE-BOUNDARIES.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/ask-matt/PHASE-BOUNDARIES.md) (v1.2) | `session-flow:workflow` continuation router, `context-guard` zones | Convergent / rejected | At parity on an ordered, first-match router with compaction last; ours adds clean-stop, user-gated background runs, instrumented zones and worker relay. Adopted one zone-gated criterion: prefer continuing when the next stage reuses this stage's reasoning as is. Rejected: triggering only at stage boundaries (`/session-flow:workflow` routes by task, mid-stage included); narrowing handoff to fewer cases (ours hands off in more); and the context-size figure, a folklore number with no official threshold behind it (our baseline is instrumented zone readings plus context-guard's declared default bands, which are defaults, not measurements, per audit amendment A1 of 2026-08-18). **Pointer**: when choosing between continuing, clearing and compacting, fetch [when your context fills up](https://code.claude.com/docs/en/context-window#when-your-context-fills-up) live. **As of**: 2026-10-02. **Recheck trigger**: that docs section starts naming a context-size threshold, or the linked `PHASE-BOUNDARIES.md` changes |
| [`teach`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/teach) | `education:teach` | Derived | The `teach-skill-comparison` audit (PR #2958) moved this row from Not adopted: the original port took the workspace file names (MISSION, GLOSSARY, RESOURCES, NOTES, and learning records kept like ADRs), the file formats, and the K-S-W, ZPD and community-delegation pedagogy with the learning-record doctrine. Rejected: the working directory as workspace (we use dedicated per-project workspace roots), the Codex sidecar, and HTML references (reference, records and glossary stay markdown). Ours adds codebase mode, the primer action, assess, the staleness doctrine, evals, slug-collision guards and a workspace-root resolution ladder. Re-adopted in that audit (education 0.7.0): storage-strength pedagogy and HTML-first interactive lessons with a shared `assets/` library, whose answer-shuffling quiz component avoids upstream's always-option-C bug ([#335](https://github.com/mattpocock/skills/issues/335)); spaced review, surfaced at resume and status from learning-record age and domain velocity, covers a scheduling gap upstream acknowledges. Copy check 2026-10-04 (`/attribution:audit`): the format files were reworded, but a unanimous panel still finds the mission, glossary, resources and learning-record formats following upstream's templates and rule lists; open, pending a rewrite decision |
| [`implement-spec`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/implement-spec) (new in v1.3) | `implementation:implement-dispatch`; `work-items:ship` with the integration-branch execution shape (`work-items/reference/execution-shape.md`) | Convergent / partial | Nothing taken. Ours has the task graph and frontier but no executor that fans a whole container out in one run. Under evaluation, none adopted: dispatched workers return red-run evidence, and a worker confirms its worktree base before the first edit. A parallel integration-branch executor is tracked, not planned: upstream's own frontier cannot advance mid-run (open issue [#936](https://github.com/mattpocock/skills/issues/936)) |
| [`pr`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/pr) (new in v1.3) | `source-control:pull-request` body contract (`reference/create.md`); `visualization:visualize` (`context/code-shapes.md`); the merge lane's door test (`autonomy/reference/guardrails/work-classes.md`) | Partial (convergent) | The shared visual menu reached us through humanlayer `show-me` ([`humanlayer-skills.md`](humanlayer-skills.md)), not through this repository. Rejected: its body template, which lacks the `## Fix`, `## Verification` and `## Related` sections our PR body contract requires. Door-based merge gating already exists on the merge lane. Under evaluation, not adopted: a door and blast-radius line in the body for the human reviewer, and routing the body through the smallest-visual menu with an opt-out |
| [`retro`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/retro) (new in v1.3) | `session-flow:retro`, `session-flow:running-retro` | Convergent | Ours predates it (`ebeda7397`, 2026-07-11) and took nothing. Compared 2026-10-04; candidates under evaluation, none adopted: routing a mechanical finding to a hook, lint or test before a written rule (upstream PR #1083), a removal pass for rules the session contradicted, and skill edits through the same approval gate. Its no-op category is already covered by `harness-config:audit-instructions` and `unhobble`. Ideas seen only in upstream reports (open issue [#1141](https://github.com/mattpocock/skills/issues/1141)) go eval-first |
| `resolving-merge-conflicts` (removed upstream in v1.3 by [`daa01d8`](https://github.com/mattpocock/skills/commit/daa01d8aa68ad5c61b68970ec2018d0ce9567be6), with no replacement; absent at the pin) | `source-control:resolve-conflicts` | Derived | Corrected 2026-10-04 from convergent: ours was added by PR #200 (`2ebc55db1`, 2026-07-15, branch `absorb/pocock-mechanisms`) after upstream's skill existed, and its steps map one to one to upstream's. An evals variant on that stranded local branch was deliberately left out (#1400). Decided: keep ours pending an eval, since `babysit-loop`, `babysit-prs` and `pull-request` route conflicts to it and it carries a repo-specific version-bump step. Next: eval assertions for the archived upstream docs page's success checks, then a with-versus-without run; delete only if the skill measures as a no-op |

## Not adopted

Each of these has a line in the [Map](#map) with its reason: the `ask-matt` router, the
`setup-matt-pocock-skills` interview, `migrate-to-shoehorn`, `scaffold-exercises`,
`setup-pre-commit`, and the three writing skills (`writing-beats`, `writing-fragments`,
`writing-shape`). Codex `agents/openai.yaml` sidecars are rejected throughout: this marketplace
targets only Claude Code, though a Codex user can still install it (see the Codex finding under
Harness findings).

Infrastructure rejected in lane 5 (v1.2):

- **The changeset version-sync script**
  ([`scripts/sync-plugin-version.mjs`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/scripts/sync-plugin-version.mjs)):
  it serves a changesets and npm release pipeline. Updated 2026-10-04: we adopted the changesets
  model (changelog fragments, one bot-maintained release PR) in
  [ADR 0048](../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md),
  but not the Changesets tool or this script. Our CI-wired
  `scripts/check-changelog-parity.sh` is the stronger gate, and `marketplace.json` carries no
  version keys that could drift.
- **Per-skill "It's working if" sections**: they belong to a per-skill docs site this marketplace
  does not build. Reopen if a docs-site build lands in this repository.
- **`writing-for-agents` and its mechanics file in bulk**: first rejected as at parity or better.
  Superseded 2026-08-17: parity holds only for the pruning and audit half, and the authoring half
  had three gaps, tracked as course lanes 7 and 8
  ([#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909),
  [#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910)). Section verdicts
  are in the decomposition table below.

No evaluation from the v1.2 audit remains open: the behavior deltas, the `wait-what` and `wizard`
ports, and the lane 5 infrastructure subset are all closed.

## writing-for-agents decomposition (re-evaluated 2026-08-17)

Upstream files read:
[`writing-for-agents/SKILL.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/writing-for-agents/SKILL.md)
and
[`SKILL-MECHANICS.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/writing-for-agents/SKILL-MECHANICS.md).
This came from the steering-section session of the AI Hero course effort (course lanes 7 to 9:
[#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909),
[#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910),
[#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911)). The structural
finding: upstream's skill applies when an agent document is being written, while our coverage was
shaped as audits; only skills had a home at writing time (`playbooks:skill-authoring`).

**Lane 7 closed 2026-08-17.** Gaps 1 and 2, and the two-loads and leading-words strands, were
designed as `docs-hygiene:write-for-agents` and built in docs-hygiene 0.17.0
([#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962)); the audit-side
completion-criteria check
([#2963](https://github.com/melodic-software/claude-code-plugins/issues/2963)) is the one open
follow-on.

**Lane 8 closed 2026-08-17.** Gap 3, invocation, is decided: the invocation-mode rubric lives at
`docs/conventions/invocation-mode/README.md` (model invocation by default plus three exception
classes). Enforcement is [#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968);
the one re-grade is [#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969).

| Upstream topic | Our surface | Verdict |
|---|---|---|
| Context pointers | `docs-hygiene:write-for-agents` (pointer doctrine at writing time), `audit-progressive-disclosure` (audit time), `playbooks:skill-authoring` (skills) | ADOPTED (adapted; #2962, docs-hygiene 0.17.0) |
| The two loads | `write-for-agents` "Budget both loads", cross-referenced from PLUGIN-PHILOSOPHY instruction economy | ADOPTED (adapted; #2962) |
| Information hierarchy | `write-for-agents` steps-versus-reference and co-location doctrine; the three-tier load-cost model covers the ladder | ADOPTED (adapted; #2962) |
| Steps and completion criteria | `write-for-agents` "Give every step a completion criterion" (writing side); the audit side rides #2963 | ADOPTED (adapted; #2962; audit side pending #2963) |
| When to split | `write-for-agents` split by sequence; the invocation axis is owned by the rubric in `docs/conventions/invocation-mode/`, linked, not restated | ADOPTED (both halves; #2962 and lane 8) |
| Leading words and negation | `write-for-agents` "Prompt the positive" | ADOPTED (adapted; #2962; tracked strand retired below) |
| Pruning: one source per fact | `docs-hygiene:extract-ssot` | PARITY+ |
| Pruning: the environment as the source of truth | `docs-hygiene:audit-derivability` (keep-as-derivation-cache verdict with drift control) | PARITY+ (ours adds drift control) |
| Pruning: relevance and sediment | `harness-config:audit-instructions`, `session-flow:reanchor`, `docs-hygiene:rename-references`, `review` doc-drift-detector | PARITY |
| Pruning: no-ops | `harness-config:unhobble` (remove the text and observe) and `audit-instructions` (judgment) | PARITY+ (v1.3 `retro` carries the same idea as one of its categories) |
| Mechanics: choosing the invocation mode | the rubric in `docs/conventions/invocation-mode/` (model invocation by default plus exception classes; the setup convention was already in PLUGIN-PHILOSOPHY); `skill-quality:check listing-budget` | ADOPTED (adapted, with the default inverted; lane 8, 2026-08-17; enforcement in #2968) |
| Mechanics: splitting by invocation | rubric section "Splitting by invocation"; #2962's when-to-split doctrine points there | ADOPTED (routed; lane 8, 2026-08-17) |
| Mechanics: router skills | rubric section "Router-skill verdict"; for people, `docs/skill-cheat-sheet.md` and `harness-ops:inventory`; `discipline:sweep-all` as the composition-router exception | REJECTED with reason (lane 8, 2026-08-17: under model invocation by default, the always-loaded skill listing already routes) |
| Invocation-reach invariant | tracked strand below | CONFIRMED (against the docs, 2026-08-17; lane 8 disposition below) |

## Tracked (event-triggered re-evaluation)

Two `writing-for-agents` strands from lane 5, tracked on events, never on dates.

- **Leading words and negation**: retired 2026-08-18, adopted as `write-for-agents` "Prompt the
  positive" (docs-hygiene 0.17.0, #2962). It shared territory with the negation port deferred in
  PR #1400 and was never tracked twice. A change to the linked upstream file is now an ordinary
  attribution concern, not an open strand.
- **Invocation-reach invariant** (upstream
  [`SKILL-MECHANICS.md`](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/writing-for-agents/SKILL-MECHANICS.md)):
  no skill can invoke a skill marked `disable-model-invocation: true`. Confirmed against the Claude
  Code docs in lane 8; `docs/conventions/invocation-mode/README.md`, "The invocation-reach
  invariant", owns the rule, so it no longer depends on upstream and the upstream-release trigger
  is retired.
  - **Pointer**: when a skill must reach another skill, fetch
    [the skills page](https://code.claude.com/docs/en/skills) live and read what
    `disable-model-invocation` removes.
  - **As of**: 2026-08-17
  - **Recheck trigger**: a repository review or audit finds a new Skill-tool or operative
    slash-command invocation of a `disable-model-invocation: true` target.

  C22 adopted, fired and resolved (#2940, lane X): a fleet audit found 57 skills marked
  `disable-model-invocation: true` and searched `SKILL.md`, evals and reference docs for Skill-tool
  invocations of them. Explicit "via the Skill tool" invocations: zero. A follow-up pass reworded
  operative slash-command instructions that targeted user-invoked skills in
  `repo-fleet-hygiene:audit` and harness-ops `inventory`, `audit-performance` and
  `audit-install-state` to "tell the user to run /X", leaving ownership and boundary tables as they
  were. Telling the user to run a command, and Skill-tool calls on model-invocable skills
  (`/toolchain:check`, `/implementation:implement-dispatch`, `/tdd:principles`,
  `/session-flow:handoff`, `/testing:run-e2e`), are not violations. A standing `skill-quality:check`
  rule was deferred (cross-plugin target resolution is costly under the single skills-root model);
  the doctrine lives in `playbooks:skill-authoring` and `skill-quality:check`. The fix for any future
  hit is the wording "tell the user to run /X". Same pass: C23 already present (our
  `curate-language` triggers already name glossary, domain term and vocabulary; one-shot, not a
  trigger) and C21 adopted (a step needing two skills makes two calls, at
  `plugins/playbooks/skills/skill-authoring/SKILL.md` and `plugins/skill-quality/skills/check/SKILL.md`).
  Since 2026-08-21 the course record's `## Lane X (#2940)` section holds a bullet per candidate and
  grades row X `PARTIAL (C21+C22 adopted; C23 already-present)`; it owns the verdicts, and this
  strand owns the C22 audit detail and the trigger above.

## Harness findings learned from this upstream

- **Desktop and web skill listing.** Our user-invoked skills are affected the same way as
  upstream's in the Claude desktop and web apps.
  - **Pointer**: when a user-invoked skill is missing from the listing on desktop or web, read
    upstream issue [#693](https://github.com/mattpocock/skills/issues/693) live.
  - **As of**: 2026-10-04 (issue open)
  - **Recheck trigger**: the issue changes state. The drift script reads trees, not issues, so this
    trigger is watched by hand.
- **Codex sidecar policy** (the `allow_implicit_invocation: false` line). Corrected 2026-10-04:
  this matters without a Codex target from us, because Codex discovers `.claude-plugin/plugin.json`
  and its skill parser ignores `disable-model-invocation`, so our user-invoked skills (75 in 62
  plugins, counted 2026-10-04) would be model-reachable there. Copilot CLI errs the other way: such
  a skill cannot be invoked even when typed. Tracked; no consumer runs either client.
  - **Pointer**: when adding a Codex sidecar, read upstream PR
    [#766](https://github.com/mattpocock/skills/pull/766) (v1.2.2) live; for the client behavior,
    read the Codex source at the release in use (`codex-rs/skills/src/parser.rs`, checked at
    `rust-v0.160.0`) and [copilot-cli#4438](https://github.com/github/copilot-cli/issues/4438).
  - **As of**: 2026-10-04
  - **Recheck trigger**: a report of this marketplace installed in Codex or Copilot CLI, or this
    marketplace adds a Codex target.

## Cross-cutting infrastructure (v1.2, not per skill)

| Item | Ours | Decision |
|---|---|---|
| Codex `agents/openai.yaml` sidecars | none: a Claude-only marketplace in a public repository (an earlier "private" reading was corrected 2026-08-18) | Not adopted; tracked because a Codex user can install this marketplace anyway, see Harness findings |
| Claude Code plugin and official marketplace listing (`claude plugins install mattpocock-skills`) | this repository is a public marketplace | Parity. Upstream's ADR 0002 (Codex plugin deferred) rests on a premise reported stale on upstream PR #565; draft PR #807 would supersede it in part |
| Per-skill docs site | `docs/` and per-plugin READMEs, no per-skill site | Not adopted; see Not adopted |
| `CLAUDE.md` provided by symlinking `AGENTS.md` | `CLAUDE.md` imports `@AGENTS.md` | No action: an import works on Windows checkouts, where a symlink can arrive as a plain file |
| Changesets with a version-sync drift gate | per-plugin semver in each CHANGELOG, `scripts/check-changelog-parity.sh` | Tool and script rejected; the changesets model adopted in ADR 0048 (see Not adopted). A drift gate over versions was noted as an idea for marketplace lint |
| Skill buckets (promoted, in progress, misc, deprecated) | plugins as units, no beta channel | Not adopted; our CHANGELOG discipline already names what replaces a retired unit. Upstream's v1.3 removal of `resolving-merge-conflicts` named no replacement, against its own deprecation note; draft upstream PR #807 would flatten the buckets, so recheck bucket names if it merges |
| User-invoked reachability rule | stated in `docs/conventions/invocation-mode/README.md`, "The invocation-reach invariant", and in `playbooks:skill-authoring` | Already landed; no action |
| Context-size figure in `ask-matt` | `context-guard` bands | Compared and rejected in the `ask-matt` row |
| Upstream issue #693 | our user-invoked skills are affected too | Pointer record in Harness findings |

## Drift/fix findings (this repository)

1. **Discharged 2026-08-21.** `plugins/planning/skills/questionnaire/SKILL.md` once called
   upstream `to-questionnaire` in progress after it had graduated; the line was removed on
   2026-08-09 in `03a827f9` (#2082).
2. **Discharged with finding 1.** The same removed lines promised a re-audit with no observable
   event, failing the upstream-drift observability bar, and the guardrails attribution named no
   trigger. This page's recheck trigger now covers every row.
3. **Open.** `work-items:triage` and `work-items:decompose` carried phrasing close to
   upstream. The provenance was recorded here in #2947; the 2026-10-04 rewrite and copy check left
   the questions noted in the `triage` and `to-tickets` rows.
4. **Baseline.** Audits target the pinned commit (the v1.3 content since 2026-10-04; v1.2.3
   before), not a release tag.
5. **Overstated parity, resolved 2026-08-17.** The lane 5 rejection of `writing-for-agents` as at
   parity covered only the pruning and audit half; the decomposition table above corrects it, and
   the gaps rode #2909 and #2910.

## Map

One line per upstream unit at the pin: relation, our owner, and what we took. A link here names a
unit; it counts as drift only when upstream removes the unit. Units we took from also have a row
above, whose links are the drift inputs.

### Engineering (20)

- [`ask-matt`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/ask-matt): none. No router skill here; the nearest are `session-flow:workflow` and the plugin listings. The router is not adopted because this marketplace has many plugins and no single main flow. Its phase-boundaries file, `PHASE-BOUNDARIES.md`, has its own row.
- [`code-review`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/code-review): partial; `review`. Rows `code-review` and PR #464. The two-worker standards-versus-spec structure is already in `quality-gate/context/self.md`, under the name `lens`.
- [`codebase-design`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/codebase-design): derived (corrected 2026-10-04 from convergent); `architecture:improve` deepening. Its module-design vocabulary, the four dependency categories and the replace-don't-layer testing rule (`DEEPENING.md`) underlie `vocabulary.md` and `dependencies.md`, and its `DESIGN-IT-TWICE.md` underlies `interface-design.md`, restated in our own words and examples on 2026-10-04. Row `codebase-design`. Absorbed upstream by v1.2: `design-an-interface`, now its `DESIGN-IT-TWICE.md` (an Ousterhout technique).
- [`diagnosing-bugs`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/diagnosing-bugs): partial (corrected 2026-08-21); `debugging:debug`, `testing:diagnose`. Row `diagnosing-bugs`.
- [`domain-modeling`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/domain-modeling): partial; `domain-driven-design:curate-language`, with the ADR three-gate test and glossary purity rule in `planning:interview`. Omitted its fixed glossary and glossary-map file names (`GLOSSARY.md` and `GLOSSARY-MAP.md` from v1.3, `CONTEXT.md` and `CONTEXT-MAP.md` before); our glossary discovery follows the consumer's convention. `curate-language` owns no ADRs, which already meets upstream request #557. Row "Grilling-family rework". Absorbed upstream by v1.2: `ubiquitous-language`.
- [`grill-with-docs`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/grill-with-docs): partial; `planning:interview` engineering mode. Took the primitive-versus-variant boundary; rounds were already ours. From v1.3 it reads and writes `GLOSSARY.md`.
- [`implement`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/implement): convergent; `implementation:implement`. Nothing taken.
- [`implement-spec`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/implement-spec): convergent or partial; `implementation:implement-dispatch`, `work-items:ship`. Nothing taken yet. Row `implement-spec`.
- [`improve-codebase-architecture`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/improve-codebase-architecture): partial; `architecture:improve`. Took the scoping filter (row), the friction questions, and the report's card, legend and diagram-pattern layout (`HTML-REPORT.md`); omitted its CDN scripts and Mermaid. Restated in our own words and examples on 2026-10-04.
- [`prototype`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/prototype): partial (corrected 2026-08-21); `prototype:explore-directions`, `prototype:pressure-test`, which predate or parallel upstream apart from the HTML demo shell from its `LOGIC.md` (row). The `prototype/<name>` branch capture was rejected (row).
- [`pr`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/pr): partial (convergent); `source-control:pull-request`, `visualization:visualize`. Row `pr`.
- [`research`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/research): convergent; `discovery:research`. Nothing taken. Upstream failure reports open on 2026-10-04: #530, #576, #995.
- [`retro`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/retro): convergent; `session-flow:retro`, `session-flow:running-retro`. Nothing taken. Row `retro`.
- [`setup-matt-pocock-skills`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/setup-matt-pocock-skills): none. Not adopted: our plugins are configured through `userConfig` and consumer docs, not a setup interview. Its v1.2 revision ([#502](https://github.com/mattpocock/skills/pull/502)) added the local layout `.scratch/<feature>/issues/<NN>-<slug>.md` and `spec.md`, and v1.3 changed its domain-docs layout to `GLOSSARY.md` (or `GLOSSARY-MAP.md`) plus `docs/adr/`; nothing taken.
- [`tdd`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/tdd): partial, relocated (lane C, C9); `tdd:principles`, `testing:write`, `planning:plan` Test strategy. Row `tdd`.
- [`to-spec`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/to-spec): partial (corrected 2026-08-21); `planning:prd`, `planning:plan`, the interview Brief and the decompose container lifecycle. C3 and C4 landed (row); C1 (synthesis without an interview) and keeping file paths out of specs were already present (corrected 2026-10-04). Not taken: extensive user stories. Renamed upstream from `/to-prd` (A9); its spec file is `spec.md`.
- [`to-tickets`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/to-tickets): partial; `work-items:decompose` (tickets are work items here). The expand-migrate-contract exception was already in decompose. Row `to-tickets`. Its one-file-per-ticket local layout is already present in our `local-markdown` tracker adapter (closed 2026-10-04).
- [`triage`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/triage): derived; `work-items:triage`. The rejected-concept ledger is a structured port of its `.out-of-scope/` ledger (row).
- [`wayfinder`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/wayfinder): partial (corrected 2026-08-21 from derived; only the name `wayfind` is derived); `planning:wayfind`. Row `wayfinder`, which records the `research/<name>` branch rejection.
- [`wizard`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/wizard): derived (lane 4); `wizard:generate` in plugin `wizard` 0.1.0, built around its `template.sh` library. Row `wizard`.

### Productivity (7)

- [`grill-me`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/grill-me): derived (behavior); `planning:interview` rounds. Row `batch-grill-me`. Upstream moved the rounds into `grilling` by v1.2.
- [`grilling`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/grilling): partial; `planning:interview` core loop. Its domain generalization was already mirrored by our domain routing. Its v1.3 separator between questions in a round was rejected as cosmetic (`aihero-course.md` lane 5).
- [`handoff`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/handoff): partial; `session-flow:handoff`, which is larger (save-point files, find-handoff, reconcile). Row "Handoff failure reports"; the narrower handoff framing was rejected in the `ask-matt` row.
- [`teach`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/teach): derived (corrected from convergent); `education:teach`, with siblings `education:explain` and `education:quiz-me`. Row `teach`.
- [`to-questionnaire`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/to-questionnaire): derived; `planning:questionnaire` (#311). Row `to-questionnaire`.
- [`wait-what`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/wait-what): derived (lane 3); `discipline:wait-what`. Its nearest neighbors are `education:explain` (altitude) and `adhd:clarify` (structure); this one re-explains at full precision; `tighten-your-output` and `caveman` shape output instead; `curate-language` owns glossary writes. Row `wait-what`.
- [`writing-for-agents`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/writing-for-agents): partial (corrected 2026-08-21); `docs-hygiene:write-for-agents`, `playbooks:skill-authoring`, the other `docs-hygiene` audits, `skill-quality:check`. Decomposition table above. Renamed upstream from `writing-great-skills` in v1.2, with its glossary merged in and `SKILL-MECHANICS.md` split out.

### Misc (4)

- [`git-guardrails-claude-code`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/misc/git-guardrails-claude-code): derived (capability); `guardrails` block-dangerous-git hook (#298), an argv-grammar parser with 190 tests at introduction and 278 at the v1.2 map's audit. Row `git-guardrails-claude-code`.
- [`migrate-to-shoehorn`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/misc/migrate-to-shoehorn): none. Not adopted: TypeScript tooling for the author's own projects.
- [`scaffold-exercises`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/misc/scaffold-exercises): none. Not adopted: specific to the author's course material.
- [`setup-pre-commit`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/misc/setup-pre-commit): none. Not adopted: toolchain and repo-hygiene territory, low value here.

### In progress (6, beta upstream)

- [`claude-handoff`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/claude-handoff): partial; `session-flow:continue-in-background` and handoff `--bg` (#76). Same direction: hand the work to a background agent (`claude --bg --name`). Draft upstream PR #647 would rename it `spawn`; still a draft on 2026-10-04.
- [`loop-me`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/loop-me): convergent; `/loop`, `work-items`, `claude-code-setup:claude-automation-recommender`. Nothing taken.
- [`setup-ts-deep-modules`](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/setup-ts-deep-modules): none; `review:architecture-guardian` checks dependency direction at review time, and `review:audit-enforceability` names dependency-cruiser on its architecture-test rung. Nothing taken; TypeScript-specific.
- `writing-beats` / `writing-fragments` / `writing-shape` ([1](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/writing-beats), [2](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/writing-fragments), [3](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/in-progress/writing-shape)): none. Not adopted: a workflow for human writing, outside this marketplace's scope.

## Related records

- [`cursor-pstack.md`](cursor-pstack.md): the pstack record, the other upstream skill collection.
- [`aihero-shipping-course.md`](aihero-shipping-course.md): the shipping course, a separate source
  from this repository (its pages are account-gated, and its recheck trigger lives there). It owns
  the candidate index (C1 to C23) and the lane verdicts. Where a candidate touches an artifact from
  this repository, its disposition sits in the owning attribution row above (`to-spec` C1 to C4,
  `to-tickets` C5 to C8 and C17, `tdd` C9 to C11, `code-review` C12 to C16, `wayfinder` C18 to C20,
  and C21 to C23 in the tracked strand) and is never re-indexed here.
- [`aihero-course.md`](aihero-course.md): the crash-course and steering-section record (its six
  original lessons and nine steering lessons, vetted as lanes with a per-lesson coverage index and
  term-adoption decisions); it keeps its own re-fetch trigger.
