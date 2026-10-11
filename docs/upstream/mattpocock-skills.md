# Upstream source — mattpocock/skills

Single source of truth for everything in this marketplace derived from
[mattpocock/skills](https://github.com/mattpocock/skills) (Matt Pocock, "AI Skills for Real
Engineers", MIT). Provenance lives HERE and in plugin CHANGELOGs — never in skill bodies, where
it is agent-facing noise. Content citations an agent actually uses (e.g. the Fowler smell
baseline in `review`) are not provenance records and stay in place.

**Last audited upstream state:** the v1.3 content at `main@d81f3a1` (2026-09-29, the merge of
upstream PR #1120), 37 skills. At audit time it was untagged: the latest tag was v1.2.3,
`package.json` still said 1.2.3, and the Changesets version PR #849 (head branch
`changeset-release/main`) that would cut 1.3.0 was open. Upstream tagged v1.3.0 and v1.3.1 on
2026-10-04 (`main@24fe0ef`), after this audit. The only content past `d81f3a1` in those releases is
upstream PR #1121 (one `ask-matt` paragraph and the `diagnosing-bugs` docs page now send post-bug
reflection to `retro`), read and recorded in the `diagnosing-bugs` row. The session-start flow
and the `ask-matt` main flow were rechecked against v1.3.1, with `main@49dd158` ahead of it on
unreleased changesets, and recorded in the map's "Session-start flow and main flow" section. On
2026-10-10 the map was re-audited at `main@49dd158` (version PR #1161 open, so the trigger below has
fired); this attribution table was not re-audited then, except the upstream issue states in the
`wayfinder` row. Also at `main@49dd158` (2026-10-10, the v1.3 video pass, issue
[#6947](https://github.com/melodic-software/claude-code-plugins/issues/6947)): the `wizard` and
`implement-spec` rows, the `chief-of-staff` watch row, and the #1123 harness finding; the other
rows only gained pointers to that pass's follow-on items. This repo's audit: the
`pocock-upstream-sync` topic. Git history of this file records *when*; this line records only *what
was audited*.

**Recheck trigger:** any of these events naming a skill in the attribution table below, or
adding, removing or renaming an upstream skill. Re-audit every affected row.

- A merge to mattpocock/skills `main` that adds a changeset. The open version PR lists every
  changeset merged since the last release, so it is the check: `gh pr list -R mattpocock/skills
  --head changeset-release/main --state open --json number,body`. Match on the head branch, never
  a PR number: each release cycle opens a new version PR.
- A mattpocock/skills GitHub release, whatever its tag spelling (`v1.3.1` today; upstream issue
  #1064 proposes `mattpocock-skills--v{version}`): `gh release list -R mattpocock/skills`,
  compared against the audited state above, never filtered by a tag pattern.

## Attribution table

| Upstream skill / source | Ours | Relation | What was taken / rejected |
|---|---|---|---|
| `to-questionnaire` (Productivity; graduated from in-progress in v1.2.0 #593) | `planning:questionnaire` | Derived | Interview-the-send invariant kept; output relocated cwd → memory slice (PII); grill→interview vocabulary; tracker-item option added. Re-audited against v1.2.3: no delta — his graduation commit is a 100%-similarity rename, his one body change (template XML-ification) is already reflected in our template, and ours is otherwise a superset (route-away, overwrite guard, role-slug multi-recipient). Qualified 2026-10-04: the XML-ified template is reflected, but upstream's worked `<question-example>` block (`to-questionnaire/SKILL.md:42-48`) is not; our `templates/questionnaire.md` has placeholders only. Deliberate divergence: upstream is user-invoked (`disable-model-invocation: true`), ours is model-invoked since the re-grade flip ([#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969)). Behavior unchanged upstream at `d81f3a1` |
| `wayfinder` | `planning:wayfind` | Partial | Fog-of-war framing + ticket-vs-fog (sharpness) distinction; REJECTED file-based map (native tracker primitives instead) and upstream tracker seam. v1.2 re-audit: ADOPTED parallel research burn-down (work-mode exception + chart-mode offer) and the in-chart no-fog bail-out; "decision ticket" term present as our "decision item" (parity under work-items vocabulary); REJECTED `research/<name>` branch (two-lane branch-naming prohibition; resolution comments + memory tier already home the findings); map-clears handoff already present-stronger (named graduation targets). Course lane W (#2939): **C18 ADOPTED** (human-facing narration names items by title, number as link or suffix; `wayfind` only, not generalized to work-items); **C19 ADOPTED** (Out-of-scope is for scope not sharpness, fog never graduates there, a wrongly scoped item is closed + one linking line); **C20 ALREADY-PRESENT** (map-as-index — a decision lives in its own item; the map gists and links, never restates). Upstream field reports, open as of 2026-10-10: [#828](https://github.com/mattpocock/skills/issues/828) (resolutions do not reach the tickets they invalidate), [#944](https://github.com/mattpocock/skills/issues/944) (the map body outgrows a size-capped field and is truncated silently). Closed: [#576](https://github.com/mattpocock/skills/issues/576) (research tickets open draft PRs), fixed 2026-10-07 by upstream `8295b8e` (research branches are pushed with no PR); [#530](https://github.com/mattpocock/skills/issues/530), the `research` skill's recursive-spawn report behind the parallel burn-down, closed not planned 2026-10-06 by `.out-of-scope/subagent-recursion.md` (the harness, not the skill, bounds subagent recursion). `8295b8e`'s other wayfinder changes are recorded in the map's row 17; this row's verdicts were not re-graded at `49dd158` |
| `batch-grill-me` / `grilling` rounds | `planning:interview` (propagated to `prd`/`design`/`plan`) | Derived (behavior) | Frontier-rounds model, facts-vs-decisions split, confirmation gate; no-grill vocabulary constraint; background fact sub-agents. v1.2 re-audit: ADOPTED ❓/➡️ emoji anchors as opt-in `userConfig` (`use_emoji_question_markers`, default off; decoration of the single verdict marker); answer-by-number dictation and any-order answering confirmed already present; REJECTED one-question-at-a-time opt-out line (his seam is the consumer's own global CLAUDE.md — platform-native, nothing for the plugin to ship). Follow-on: [#6946](https://github.com/melodic-software/claude-code-plugins/issues/6946), an eval case for a question whose recommendation is negative (upstream #706); a wording rule follows only if it fails. |
| grilling-family rework (upstream PR #532) | `planning:interview`, `architecture:improve` | Partial | decision-tree rename, domain-routing, primitive-vs-variant boundary; ADR 3-gate + glossary purity previously recorded as house additions — **annotated 2026-08-18 (lane 5 audit-answers pass, two independent validators):** current upstream main's `domain-modeling` carries both near-identically; direction/timing unverifiable at annotation time (upstream git history behind a blocked API) — treat as convergent-or-derived, not house-original |
| `git-guardrails-claude-code` (misc) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Capability adopted; substring-matching implementation REJECTED wholesale (false-blocks) — house argv-grammar parser instead |
| upstream PR #464 (review checklist) | `review` code-reviewer Fowler baseline | Pointer | Surfaced the idea; content re-derived from Fowler, *Refactoring* 2nd ed. ch. 3 — no upstream phrasing |
| `code-review` (course flow skill; distinct from PR #464 above) | `review` — `quality-gate` lenses, `fanout`, code-reviewer agent | Partial | Course lane D (#2937): **C12 ADOPTED-corrected** (spec axis as a 9th `quality-gate` lens, `context/spec.md` owning the missing / scope-creep / wrong enum; branch-scoped — the container-scoped consumer was filled later by the close-out lens, not this one); **C13 ALREADY-PRESENT + one edit** (two-axis intent already implemented as `fanout`'s two-axis presentation; the proposed never-merge/never-rerank rule WITHDRAWN — it negates the normalization pipeline `fanout` exists to run; `axis` vs `lens` vocabulary recorded once in `review/context/severity.md`); **C14 ADOPTED-corrected** (spec-source discovery ladder, with bare-`#N` validation-and-promotion, provider-mechanic read, and a topic-slug rung); **C15 PARTIAL** (fail-fast preflight ported, mode-scoped with `allowed-tools` widened; `fanout`'s untracked-only stop deliberately NOT copied); **C16 ALREADY-PRESENT** (both suppression halves already in `code-reviewer.md`). Map row 2 |
| upstream issues #186/#306/#617/#482 (handoff failures) | `session-flow` handoff claim-provenance + constraint re-scan rules | Derived (failure corpus) | Two rules adopted from incident threads; rest rejected (verdicts on issue #1477) |
| `triage` + its `.out-of-scope/` KB (`OUT-OF-SCOPE.md`) | `work-items:triage` | Derived (structured port) | "A PR is an item with attached code" ≈ upstream's "a PR is an issue with attached code"; state-machine framing convergent. Corrected in lane 5 — this row previously claimed "no structured port", which is provably false: the rejected-concept ledger (work-items 0.6.0; triage's ledger check + won't-fix/already-implemented outcomes) is a structured port of upstream's `.out-of-scope/` KB — one-file-per-concept, concept-similarity-not-keyword matching, never-ledger-built-features, and the near-verbatim "so the same request doesn't return as fresh code" (upstream `OUT-OF-SCOPE.md:86`) map one-to-one; ours is a superset. The v1.2 `.out-of-scope/` adoption candidate (M15) is therefore REJECTED as already-adopted; provenance row corrected only — no `work-items` behavior change (the topic plan's out-of-scope bars it) |
| `to-spec` | `planning:plan` / `planning:prd` Brief + `work-items:decompose` container lifecycle | Partial | Course lane A (#2934): **C1 ALREADY-PRESENT** (no-interview pure-synthesis mode — `planning:interview` synthesizes directly when intent is clear; `plan`'s empty-argument default finalizes without re-interviewing); **C2 PARTIAL, routed to lane C** (#2936 — seam-sketch-before-spec lands beside C9; the "ideal number of seams is one" absolutism REJECTED, folklore-figure posture); **C3 PARTIAL** (optional `## Testing decisions` section with prior-art test pointers adopted; the "LONG, numbered, extremely extensive" directive stays excluded); **C4 ADOPTED (gate-added variant)** (spec publishes to the tracker as a `work-map` container with slices as native sub-items; upstream's gate-free publish excluded). Course-only "archive-your-specs" ADOPTED as archival-by-closure. Map row 14 |
| `to-tickets` | `work-items:decompose` | Partial | Vertical-slice / tracer-bullet vocabulary overlaps upstream and the seam plumbing is house-built — but "influence (vocabulary)" understated it, and disagreed with map row 15, which already graded this PARTIAL. Lane B (#2935) adopted four **mechanics**, not just phrasing: prefactor-as-blocker (C5, `decompose/SKILL.md:63`), the one-fresh-context-window sizing bar (C6, `:65`), the integration-branch fallback (C7, `:98`), and the PR-variant agent brief (C17, `agent-brief.md:82`). Only C8 — "work the frontier" (`:102`, `:201`) — is vocabulary. Lane B verdicts: **C5, C6, C7, C8, C17 all ADOPTED** |
| `tdd` / `tests.md` / `mocking.md` | `planning:plan` Test strategy, `tdd:principles`, `testing:write`, `review` code-reviewer | Partial | Course lane C (#2936): **C9 PARTIAL, relocated** (pre-agreed-boundary discipline lands in `plan`'s existing Test strategy element — deliberately NOT phrased as "seam" (fleet-registered vocabulary) and NOT hosted by `implementation:phase-verifier`; upstream's hard consent gate softened to a `DEVIATIONS.md` record an unattended run can satisfy); **C10 ALREADY-PRESENT (prose)** (tautological-test anti-pattern at `anti-patterns-khorikov.md` + `testing/write`; the prose-only coverage was an overstatement corrected in-lane, and the executable half landed as a `code-reviewer.md` criterion, `review` 0.24.0, ceding the textually-identical core to `cant-fail-scan.sh` when that scan's output is in context); **C11 ALREADY-PRESENT + one clause** (`test-doubles.md` has carried SDK-style-interfaces-over-generic-fetchers since `85aa8066`; added only the missing subordination clause — the shape rule never widens *what* gets mocked). Zero-assembly chain doc REJECTED with reasons (the drafted chain was factually wrong). Map row 13 |
| `improve-codebase-architecture` YAGNI scoping filter (v1.2 #533) | `architecture:improve` deepening Phase 1 | Partial | ADOPTED scope-before-scanning: user-named direction scopes the scan, else recent-commit hot spots pull attention first (precomputed context widened to 20 commits). REJECTED his glossary file reference (`CONTEXT.md` at v1.2.3, renamed `GLOSSARY.md` in v1.3; our glossary-discovery ladder instead). Corrected 2026-10-04: the HTML report was ADOPTED (self-contained file in a temp dir, three recommendation badges; `architecture/skills/improve/actions/deepening.md:66-85`, since `30cf0343f`); only the CDN Tailwind and Mermaid loading is rejected. Upstream v1.3 removed the inbound `diagnosing-bugs` post-mortem hand-off to this skill (`1dab982`) |
| `diagnosing-bugs` (v1.2.3 Redact + tagged logs) | `debugging:debug`, `testing:diagnose` | Partial | ADOPTED the redaction guard in both skills (secrets `<REDACTED>` before any shown command/output/artifact; env-var credentials; signal-lines-only quoting) and the `[DEBUG-a4f2]` tagged-log convention in `testing:diagnose` (already present in `debugging:debug`). Re-evaluated at `d81f3a1` (2026-10-04): the ranked construction strategies and 3-5 ranked hypotheses are ALREADY-PRESENT (`debugging/skills/debug/SKILL.md:61-72`, `:112-122`). Real gaps, under evaluation: upstream's minimize step (`diagnosing-bugs/SKILL.md:78-86`; our `:152` and `:159` refer to a minimized repro no phase produces) and its Phase 1 completion criterion (one named command, already run, red output shown; `:59`, present since v1.2.3). Phase 6: upstream removed the post-mortem hand-off in `1dab982` (2026-08-15, upstream PR #880, fixing #453) because it was a Skill-tool call to a user-invoked skill from an often-unattended flow; graded KEEP ours (REJECT the removal), since our Phase 6 (`SKILL.md:163-180`) files the finding and calls no skill. Upstream PR #1121 (merged 2026-10-04, released in v1.3.1, closing issue #1117) now sends the "what would have prevented this?" question to `retro` after the fix. Follow-on: [#6945](https://github.com/melodic-software/claude-code-plugins/issues/6945), Phase 6 routing for check-shaped prevention answers. |
| `wait-what` (Productivity, NEW in v1.2 #751) | `discipline:wait-what` | Derived | Ported near-verbatim (one-sentence re-pitch body: back up, add missing context, ASD-STE100 register + inline gloss, ubiquitous language) as a declared non-corrector species in `discipline` beside `tighten-your-output`/`mind-your-maxims` — home chosen on the blame axis (the drift is the model's output, not the user's comprehension). Name KEPT with an explicit PLUGIN-PHILOSOPHY naming-exception entry (utterance-is-mechanism + upstream muscle-memory parity; a 5-generator/3-judge naming tournament's grammar-clean winner `re-pitch` was declined by the user). REJECTED his fixed glossary filenames: `CONTEXT.md` at v1.2.3, renamed `GLOSSARY.md` / `GLOSSARY-MAP.md` in v1.3 (`006a52b`) with no fallback for the old names (open upstream issue [#1153](https://github.com/mattpocock/skills/issues/1153), no migration path). Ours keeps format-externalized discovery: the nearest glossary or context map per the consumer's convention, plain technical English when none exists (`discipline/skills/wait-what/SKILL.md:15-17`). Re-checked 2026-10-04: his v1.3 map-following (`GLOSSARY-MAP.md` to the right `GLOSSARY.md`, upstream PR #904) now matches ours, so the rejection covers only the fixed names. Shape evidence: his X thread (status 2084753070437609606 → 2084941367659168064 → 2085681281795232026) — the same instruction failed as passive global CLAUDE.md AND as an output style; only the on-demand skill works, so the register text lives in the body, invoked at the moment of loss |
| `wizard` (Engineering; graduated from in-progress in v1.2) | `wizard:generate` | Derived | PORTED (lane 4) as a new single-capability plugin `wizard` 0.1.0, hardened. Kept: the 4-step scope/map/author/verify process, the fixed never-hand-edited library above the `STAGES` marker, model-invoked posture with the explicit non-trigger fence, gh-absence graceful degradation, ephemeral-by-default doctrine, agent-authors-never-runs doctrine. Hardened beyond upstream (deltas enumerated in `plugins/wizard/CHANGELOG.md` 0.1.0): mandatory human read-and-approve of the full STAGES block before `chmod +x`; https-only `open_url` (also closes a Windows UNC/NTLM leak via explorer.exe); `/dev/tty` fail-closed prompts (retires a verified multi-line-paste confirm bypass and `pause`'s fail-open at EOF); quoted `0600` `.env` writes + gitignore assert + trap-cleaned atomic temp; repo-resolved/confirmed `--repo`-explicit gh writes with stderr surfaced and empty values refused; key-name validation; readline on non-secret asks (fixes upstream #741 where safe); names-only live-`.env` scoping with the secrets-and-context property stated honestly. REJECTED: Codex `agents/openai.yaml` sidecar (no Codex target — standing precedent). Upstream status 2026-10-04: the template dropped "time remaining" (v1.2.3), but the docs page still advertises it (`docs/engineering/wizard.md:44`), so a later sync must not bring it back. Upstream bugs ported as fixes: [#1041](https://github.com/mattpocock/skills/issues/1041) (`write_env` never assigns the shell variable) and [#811](https://github.com/mattpocock/skills/issues/811) (a symlinked `.env` is replaced, not written through) in 0.6.4; [#1142](https://github.com/mattpocock/skills/issues/1142) (editing the script mid-run re-runs or kills it), fixed upstream in `49dd158` by wrapping the stages in `run_wizard`, ported with `exit` moved inside the function so a formatter that splits `run_wizard "$@"; exit` cannot undo it |
| `prototype` `LOGIC.md` shareable-HTML demo (Engineering, v1.2) | `prototype:pressure-test` | Partial | ADOPTED (lane 5) the audience-routed HTML demo shell: TUI stays default; when the driver is a non-developer (designer, PM, domain expert) or no terminal fits, the disposable shell over the same portable pure logic module is one self-contained `file://` page — domain-language labels, labeled state panel re-rendered per click, free-play buttons, guided-walkthrough scenarios resetting to a known initial state — under explore-directions' existing HTML-substrate constraint set reused verbatim-in-spirit (restrictive CSP meta tag, ephemeral `mktemp -d` / `%LOCALAPPDATA%\Temp` placement, synthetic data only, discard after the markdown capture). prototype 0.5.0. REJECTED the other half of upstream's step 5: the throwaway-branch "primary source" capture that keeps the prototype re-runnable on a branch — a two-lane branch-naming posture violation that also contradicts the plugin's delete-when-done discipline (`plugins/prototype/context/discipline.md`, "Delete or absorb when done") |
| ask-matt `PHASE-BOUNDARIES.md` (v1.2) | `session-flow:workflow` continuation router + `context-guard` zones | Convergent / rejected | Re-read at `84fdeff`. At parity: the ordered first-yes-wins router and compaction last with a focus; ours adds clean-stop, user-gated background, instrumented zones, worker relay. ADOPTED one zone-gated criterion: prefer continue when the next stage consumes this stage's reasoning verbatim. REJECTED the boundary-only trigger (`/session-flow:workflow` routes by task, mid-stage included), the "handoff only for what travels" narrowing (`/session-flow:workflow` hands off in more cases than his travel list), and the ~150k smart-zone figure (self-declared-debated folklore; no official numeric threshold exists; our baseline is instrumented zone readings plus context-guard's declared judgment-default bands with named provenance (corrected 2026-08-18 per audit amendment A1: the bands are declared defaults, not measurements; only zone readings are measured), his dictionary entry noted as one more folklore anchor). Docs topic: [when your context fills up](https://code.claude.com/docs/en/context-window#when-your-context-fills-up). As-of 2026-10-02 |
| `teach` (Productivity) | `education:teach` | Derived | Corrected by the `teach-skill-comparison` topic audit (PR #2958) — this row previously sat under "Not adopted", which is provably false: the original port took his workspace vocabulary (MISSION / GLOSSARY / RESOURCES / NOTES + learning records as "teaching ADRs"), near-verbatim FORMAT-spec content, and the K-S-W / ZPD / community-delegation pedagogy with learning-record doctrine. REJECTED: cwd-as-workspace (dedicated per-project workspace roots instead), Codex `agents/openai.yaml` sidecar (standing precedent), HTML references (the durable trio — reference, records, glossary — stays markdown). ADDED house-built: codebase mode, primer action, assess, staleness doctrine, evals, slug-collision guards, workspace-root resolution ladder. RE-ADOPTED in the same audit (education 0.7.0): storage-strength pedagogy (fluency-vs-storage, desirable-difficulty triad, knowledge/skills asymmetry, equal-length quiz answers) and HTML-first interactive lessons with a shared `assets/` library (answer-shuffling quiz component — fixes his #335 class of always-option-C bug); his acknowledged no-review-scheduling gap is out-executed via spaced review surfaced at resume/status from learning-record age × domain velocity |
| `codebase-design` (Engineering) | `architecture:improve` deepening vocabulary (`research/deepening/vocabulary.md:9-30`) | Derived | Corrected 2026-10-04 from the map's earlier CONVERGENT / "not ported": the Module, Interface, Depth, Seam, Adapter, Leverage and Locality terms, the deletion test and "one adapter = hypothetical seam, two = real" were ported near word for word when the plugin was added (`30cf0343f`, 2026-07-10). Upstream open issues [#449](https://github.com/mattpocock/skills/issues/449) and [#458](https://github.com/mattpocock/skills/issues/458) report it used as a session driver and ask how to apply it |
| `implement-spec` (Engineering, graduated in v1.3) | `implementation:implement-dispatch` (phase waves inside one item); `work-items:ship` with the integration-branch execution shape (`work-items/reference/execution-shape.md`), which is sequential and operator-driven | Convergent / Partial | Nothing taken yet. Upstream runs a container's whole ready frontier in one run (worktree per ticket, one integration branch, final `code-review`); ours has the task graph and frontier but no executor that fans a container out. That executor is tracked as [#6942](https://github.com/melodic-software/claude-code-plugins/issues/6942) (`/work-items:ship run #N`), after [#6412](https://github.com/melodic-software/claude-code-plugins/issues/6412) (item-list dispatch with dependency order and a base parameter). Rechecked at `main@49dd158` (2026-10-10): upstream's open issue [#936](https://github.com/mattpocock/skills/issues/936) (the frontier cannot advance mid-run because tickets close only when the PR merges) does not apply here, since our integration-branch shape closes each item as a checkpoint when it lands (`work-items/reference/execution-shape.md`, "Closing a checkpoint records durable progress"). The worker's worktree-base check is present for the default branch (`implementation/skills/implement-dispatch/SKILL.md` item 9, `implementation/agents/implementer.md`); a named integration-branch base needs a parameter, carried by #6412, because harness `isolation: worktree` cannot base a worktree on a named branch ([sub-agents docs](https://code.claude.com/docs/en/sub-agents), `isolation` row; upstream #942). Upstream's one full-run report, closed issue [#1010](https://github.com/mattpocock/skills/issues/1010), found: merge inline and dispatch a merger subagent only on conflict, keep the orchestrator from diagnosing failing checks inline, and name branches for discovered work and Spec-axis findings; these are inputs to #6942, none adopted here. Still a candidate, not adopted: dispatched workers return red-run evidence (upstream's #1035 fix, the implementer runs `tdd`) |
| `pr` (Engineering, graduated in v1.3) | `source-control:pull-request` (body contract, `reference/create.md`); `visualization:visualize` (`context/code-shapes.md`, the same humanlayer `show-me` menu, recorded in [`humanlayer-skills.md`](humanlayer-skills.md)); the merge lane's door test on the actual diff (`autonomy/reference/guardrails/work-classes.md`) | Partial (convergent) | Same `show-me` source reached us through humanlayer, not through him. REJECTED his body template: it drops the `## Fix`, `## Verification` and `## Related` sections our PR body contract requires. Door-based merge gating is already present on the merge lane. REJECTED a one-way/two-way door and blast-radius line in the body for the human reviewer: PR risk goes to the risk-only explain-change action instead (#6943). Under evaluation, not adopted: routing the PR-body path through the smallest-visual menu with an opt-out (his first version said a forced diagram is worse than none). Follow-on: [#6934](https://github.com/melodic-software/claude-code-plugins/issues/6934) (a `Left out:` line in Verification), [#6943](https://github.com/melodic-software/claude-code-plugins/issues/6943) (risk-only explain-change), [#6997](https://github.com/melodic-software/claude-code-plugins/issues/6997) (pull-request eval fixture). |
| `retro` (Engineering, graduated in v1.3) | `session-flow:retro`, `session-flow:running-retro` | Convergent | Ours predates his (`ebeda7397`, 2026-07-11, against his `8fa1886`, 2026-08-24) and took nothing from it. His seven categories (Navigation, Automated checks, Coding standards, Global AGENTS.md, Tool economy, No-ops, Information access; `retro/SKILL.md:17-23`) were compared on 2026-10-04. Gaps in ours, candidates under evaluation, none adopted: a deterministic-check route (a mechanical finding becomes a hook, lint or test before a written rule; upstream PR #1083), a removal pass for rules the session contradicted or made obsolete, and skill edits routed through the same approval gate. His No-ops category is not a gap (`harness-config:audit-instructions` and `unhobble` cover it). Ideas seen only in upstream reports, such as reading subagent sessions after `implement-spec` (open issue [#1141](https://github.com/mattpocock/skills/issues/1141)), go eval-first before any adoption. Follow-on: [#6944](https://github.com/melodic-software/claude-code-plugins/issues/6944), the deterministic-check route. |
| `resolving-merge-conflicts` (Engineering; removed upstream in v1.3) | `source-control:resolve-conflicts` | Derived | Corrected 2026-10-04 from the map's earlier CONVERGENT / "not ported": ours was added in source-control 0.3.0 by PR #200 (`2ebc55db1`, 2026-07-15, branch `absorb/pocock-mechanisms`, the external-skills census), after his skill (`81ddacb`, 2026-06-02), and his five steps map one to one to ours, including "always resolve; never `--abort`". Upstream removed the skill in `daa01d8aa68ad5c61b68970ec2018d0ce9567be6` ("nothing replaces it"; the agent handles conflicts without a skill); its docs page stays up marked archived (`docs/engineering/resolving-merge-conflicts.md:1`). DECIDED: keep ours pending an eval. `babysit-loop`, `babysit-prs` and `pull-request` route conflicts to it, it carries a repo-specific version-bump step, and no run has measured it with versus without the skill. Next step: add eval assertions for the archived page's "It's working if" items (finish every stop of a multi-commit rebase, add nothing that was on neither branch, quote PR or issue sources), then run a with/without comparison; delete only if the skill measures as a no-op. The paid with/without run is [#6939](https://github.com/melodic-software/claude-code-plugins/issues/6939). |
| `chief-of-staff` (in-progress, not graduated; `skills/in-progress/chief-of-staff/SKILL.md` at `main@49dd158`) | `session-flow:orchestrate`; the environment-improvement track overlaps `session-flow:retro` follow-on [#6944](https://github.com/melodic-software/claude-code-plugins/issues/6944) | Watch | Nothing taken. A long-running-goal posture on two tracks (tactical, and strategic: change the environment so the next task goes better), all work in background subagents, communication through context pointers, and a no-workarounds rule; convergent with `orchestrate` plus the retro idea. Not adopted while upstream is still editing it (five commits 2026-10-05 to 2026-10-06, "More playing around"). Recheck trigger: the skill moves out of `skills/in-progress/` or is removed |

## Not adopted (decided, with reasons)

`ask-matt` router (marketplace shape differs), `setup-matt-pocock-skills` (we configure via
`userConfig` + consumer docs), `migrate-to-shoehorn` /
`scaffold-exercises` / `setup-pre-commit` (personal/low-value), writing-beats/-fragments/-shape
(out of scope), Codex `agents/openai.yaml` sidecars (we target only Claude Code; a Codex user can
still install this marketplace, see the Codex finding under Harness findings). (`teach` moved to the
attribution table — the `teach-skill-comparison` topic audit established it as Derived.)

Lane-5 infra rejections (v1.2):

- **Version-sync script** (his `scripts/` changeset-version sync): serves upstream's
  changesets/npm release pipeline. Updated 2026-10-04: we adopted the changesets model (changelog
  fragments, one bot-maintained release PR) in
  [ADR 0048](../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)
  (accepted 2026-10-03, not yet built), but not the Changesets tool or this sync script. Our CI-wired
  `scripts/check-changelog-parity.sh` (`.github/workflows/ci.yml` changelog-parity job) is the
  stronger gate; the version one-home doctrine holds — `marketplace.json` carries no version
  keys to drift.
- **"It's working if" sections** (per-skill success blurbs): they decorate a per-skill docs site
  this marketplace doesn't build (docs-site build is out of scope per the topic plan). Reopen
  condition: a docs-site build landing in this repo — recorded here, deliberately not a TRACK
  row. Their content is still used: when a row is re-audited, the upstream docs page's
  "Common questions" and "It's working if" items for that skill become eval assertions for our
  derived skill, as in the `resolving-merge-conflicts` row; there is no dedicated sweep.
- **`writing-for-agents` / `SKILL-MECHANICS.md` bulk**: originally rejected at parity or
  stronger (v1.2 lane 5). **Superseded 2026-08-17** by the steering-section re-evaluation:
  parity holds only for the pruning/audit half; the authoring half carries three gaps, tracked
  as course lanes 7–8
  ([#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909),
  [#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910)).
  Section-by-section verdicts: the decomposition table below.

The v1.2 behavior deltas (owned-skill lane), the `wait-what` port, the `wizard` port, and the
infra subset (lane 5: shareable-HTML logic shell adopted — prototype row above; version-sync
script and "It's working if" rejected above; `.out-of-scope/` KB rejected as already-adopted —
triage row above; two writing-for-agents strands tracked below) are all closed — no evaluations
from the v1.2 audit remain open.

## writing-for-agents decomposition (re-evaluated 2026-08-17)

Steering-section session of the AI Hero course effort (course lanes 7–9:
[#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909) /
[#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910) /
[#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911)). Upstream
re-verified current at v1.2.3 — no release past `84fdeff`; unreleased main drift (upstream
PRs 878/880) is recorded in the pocock-course-lanes pre-lane recheck. Both were later released in
v1.3.0 (2026-10-04). Verdict per upstream
section — where each concern lives here, or the recorded gap. The structural finding behind
the supersession: upstream fires at the *authoring* moment ("creating or editing skills, or
modifying AGENTS.md or CLAUDE.md") while our coverage is *audit*-shaped; only skills have an
authoring-moment home (`playbooks:skill-authoring`).

**Lane 7 closed 2026-08-17**: gaps 1–2 and the two-loads/leading-words strands are
design-locked as `docs-hygiene:write-for-agents`
(build:
[#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962) +
[#2963](https://github.com/melodic-software/claude-code-plugins/issues/2963), the audit-side
completion-criteria criterion). **#2962 built (docs-hygiene 0.17.0)**: the gap-1/2 verdict
cells below are ADOPTED; #2963's audit-side criterion remains the one open follow-on.

**Lane 8 closed 2026-08-17**: gap 3 (invocation) is decided — invocation-mode rubric homed at
`docs/conventions/invocation-mode/README.md` (model-invoked default + three exception classes); enforcement filed as
[#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968), the one re-grade
flip as [#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969).

| Upstream section | Our surface | Verdict |
|---|---|---|
| Context pointers (wording-as-trigger, branches, front-loaded leading word) | `docs-hygiene:write-for-agents` (authoring-time, branch-covering front-loaded pointer doctrine) + `audit-progressive-disclosure` (audit-time criteria) + `playbooks:skill-authoring` (skills) | ADOPTED (adapted; #2962, docs-hygiene 0.17.0) |
| The two loads (context load / cognitive load) | `write-for-agents` "Budget both loads" + PLUGIN-PHILOSOPHY Instruction-economy cross-reference | ADOPTED (adapted; #2962) |
| Information hierarchy (steps vs reference, ladder, co-location, sprawl) | `write-for-agents` steps-vs-reference + co-location doctrine; three-tier load-cost model carries the ladder | ADOPTED (adapted; #2962) |
| Steps and completion criteria (clarity, demand, premature completion, post-completion steps, legwork) | `write-for-agents` "Give every step a completion criterion" (write-side); audit-side criterion rides #2963 | ADOPTED (adapted; #2962 — audit-side pending #2963) |
| When to split (by sequence / by invocation) | `write-for-agents` split-by-sequence; invocation axis owned by the rubric (`docs/conventions/invocation-mode/`), pointed at, never restated | ADOPTED (both halves; #2962 + lane 8) |
| Leading words + negation | `write-for-agents` "Prompt the positive" | ADOPTED (adapted; #2962 — tracked strand retired below) |
| Pruning: single source of truth | `docs-hygiene:extract-ssot` | PARITY+ |
| Pruning: environment-as-truth ("cache") | `docs-hygiene:audit-derivability` (keep-as-derivation-cache verdict + drift control) | PARITY+ (stronger — cache without drift control is not a cache) |
| Pruning: relevance / sediment | `harness-config:audit-instructions`, `session-flow:reanchor`, `docs-hygiene:rename-references`, `review` doc-drift-detector | PARITY |
| Pruning: no-ops (model-relative, run-the-document test) | `harness-config:unhobble` (empirical — operationalizes his remove-and-observe test) + `audit-instructions` (judgment) | PARITY+ (v1.3 `retro` carries the same idea as its No-ops category, `retro/SKILL.md:22`) |
| MECHANICS: invocation choice | rubric at `docs/conventions/invocation-mode/` (model-invoked default + exception classes; the setup convention was already documented in PLUGIN-PHILOSOPHY, contra this row's earlier "undocumented" reading); `skill-quality:check listing-budget` instrument | ADOPTED (adapted — inverted default; lane 8, 2026-08-17; enforcement → #2968) |
| MECHANICS: splitting by invocation | rubric § Splitting by invocation; #2962's when-to-split doctrine points there | ADOPTED (routed; lane 8, 2026-08-17) |
| MECHANICS: router skills | rubric § Router-skill verdict; human-side answer = `docs/skill-cheat-sheet.md` + `harness-ops:inventory`; composition-router carve-out (`discipline:sweep-all`) | REJECTED with reason (lane 8, 2026-08-17 — the always-present listing is the router under a model-invoked default) |
| Invocation-reach invariant | tracked strand (below) | CONFIRMED (docs-verified 2026-08-17; lane 8 disposition below) |

## Tracked (event-triggered re-evaluation)

Two `writing-for-agents` strands from v1.2 (lane 5) — tracked on events, never dates. Since
2026-08-17 each also has a disposition path through the steering course lanes; the event
triggers stand until the owning lane records the disposition:

- **Leading-words + negation doctrine** (upstream `writing-for-agents/SKILL.md:61-74`:
  pretrained "leading words" as compact behavior anchors; prompt the positive — prohibition
  drags the banned behavior into context). Not double-tracked: this is the same territory as
  the deliberate deferral already recorded in PR #1400 (the skill-quality
  negation/negative-space port deferred from that session's gap scan) — this record
  cross-links that deferral rather than opening a second ledger entry. Trigger: a
  mattpocock/skills release whose changeset names `writing-for-agents`.
  **RETIRED (2026-08-18): adopted as `write-for-agents` "Prompt the positive"
  (docs-hygiene 0.17.0, #2962). The release-named recheck trigger now applies only as an
  ordinary attribution-table row concern, not an open strand.**
- **Invocation-reach invariant** (upstream `SKILL-MECHANICS.md:10`: a user-invoked skill —
  `disable-model-invocation: true` — can be invoked by no other skill).
  **Disposition (lane 8, 2026-08-17): CONFIRMED against current official docs**
  (code.claude.com/docs/en/skills, fetched 2026-08-17): `disable-model-invocation: true` →
  "Description not in context, full skill loads when you invoke"; "By default, Claude can invoke
  any skill that doesn't have `disable-model-invocation: true` set"; the flag "removes the skill
  from Claude's context entirely" — and it also blocks subagent preload and (v2.1.196+)
  scheduled-task prompts. The upstream-release trigger is retired (the invariant no longer
  depends on upstream's wording — it is docs-confirmed and owned by
  `docs/conventions/invocation-mode/README.md` § The invocation-reach invariant).
  **C22 ADOPTED — fired-and-resolved
  (#2940 / Lane X):** fleet audit enumerated **57** skills with
  `disable-model-invocation: true` and searched `SKILL.md`, evals, and reference docs for
  Skill-tool invocation of those names (patterns such as "invoke `/plugin:skill` via the Skill
  tool", "Call the Skill tool" + target, "Skill tool" + `:setup`). The explicit "via the Skill
  tool" form is still **zero**. A follow-up pass also reworded operative slash-command
  instructions against user-invoked-only targets in `repo-fleet-hygiene:audit` and
  `harness-ops` `inventory` / `audit-performance` / `audit-install-state` (agent-operative
  "execute/route/hand to /X" → "tell the user to run /X"; ownership and Question|Owner
  boundary tables left intact). Human-relay phrasing ("tell the user to run /X",
  "offering to run `/plugin:setup`") and Skill-tool hits on model-invocable skills
  (`/toolchain:check`, `/implementation:implement-dispatch`, `/tdd:principles`,
  `/session-flow:handoff`, `/testing:run-e2e`) are non-violations. Standing
  `skill-quality:check` automation deferred (cross-plugin target resolution is not cheap under
  the single skills-root model); doctrine lines live in `playbooks:skill-authoring` and
  `skill-quality:check`. Canonical rewording if a future hit appears: "tell the user to run /X".
  Same Lane X pass: C23 curate-language trigger comparison vs upstream artifact-anchored
  `domain-modeling` rewording is **ALREADY-PRESENT** (ours already name glossary / domain term /
  vocabulary) — one-shot, not a re-evaluation trigger. Same lane's **C21 ADOPTED**:
  one-skill-per-call phrasing (a step needing two skills is two calls, not one call naming
  two) landed at `plugins/playbooks/skills/skill-authoring/SKILL.md:180` and
  `plugins/skill-quality/skills/check/SKILL.md:161`. **Granularity caveat resolved
  (2026-08-21):** the course SSOT — which owns lane verdicts — now carries a `## Lane X (#2940)`
  section with a bullet per candidate, and its verdict-table row X was corrected from a flat
  ADOPTED to `PARTIAL (C21+C22 adopted; C23 already-present)`, matching how every other lane
  holding an already-present candidate is graded. The two records agree: the course SSOT owns
  the verdicts, this strand owns the audit detail behind C22 and the re-trigger below.
  Re-trigger (audit-side only; the upstream-release trigger is retired per the lane 8
  disposition above): a repo review/audit surfacing a new Skill-tool or operative
  slash-command invocation of a `disable-model-invocation: true` target re-opens this strand.

## Harness findings learned from this upstream (recheck-worthy)

- **Upstream issue [#693](https://github.com/mattpocock/skills/issues/693):** Claude's desktop
  and web surfaces drop user-invoked skills from the skill listing. Affects OUR user-invoked
  skills on those surfaces too. Recheck when that issue changes state.
- **Codex dual-harness gotcha (upstream v1.2.2, PR #766):** `policy.allow_implicit_invocation:
  false` in an `agents/openai.yaml` sidecar hides a *model-invoked* skill from Codex entirely —
  the policy line belongs only on user-invoked skills. Relevant if anyone installs this
  marketplace in Codex, which needs no Codex target from us: Codex discovers
  `.claude-plugin/plugin.json` (`codex-rs/exec-server-protocol/src/protocol.rs:49-53` at
  `rust-v0.160.0`), and its skill parser reads only `name`, `description` and
  `metadata.short-description` (`codex-rs/skills/src/parser.rs:7-20`), so our 75 skills with
  `disable-model-invocation: true` (in 62 plugins, of 351 `SKILL.md` files, counted
  2026-10-04) would be model-reachable there. Copilot CLI honors the field too strictly: such a
  skill cannot be invoked even when typed
  ([copilot-cli#4438](https://github.com/github/copilot-cli/issues/4438), open). TRACKED, no
  consumer runs either client; recheck on a Codex or Copilot install report.
- **Upstream issue [#1123](https://github.com/mattpocock/skills/issues/1123):** "call the Skill
  tool" phrasing is not harness-neutral; Codex CLI and pi have no Skill tool (issue comments).
  Upstream went the other way since: PR #1189 (merged 2026-10-06) moved `implement` to Skill-tool
  phrasing, and `.agents/invocation.md` still argues for it. Our wording is unchanged: this
  marketplace targets Claude Code, which has the Skill tool, and no consumer runs Codex or pi.
  Open as of `main@49dd158` (2026-10-10). Recheck when #1123 changes state or on a Codex or pi
  install report.

## Follow-on items from the v1.3 video pass

The 2026-10-10 pass over the v1.3 video and `main@49dd158` filed these items; rows above point at
the ones they touch, and each item holds its own decision and scope:
[#6934](https://github.com/melodic-software/claude-code-plugins/issues/6934), [#6935](https://github.com/melodic-software/claude-code-plugins/issues/6935), [#6936](https://github.com/melodic-software/claude-code-plugins/issues/6936),
[#6937](https://github.com/melodic-software/claude-code-plugins/issues/6937), [#6938](https://github.com/melodic-software/claude-code-plugins/issues/6938), [#6939](https://github.com/melodic-software/claude-code-plugins/issues/6939),
[#6940](https://github.com/melodic-software/claude-code-plugins/issues/6940), [#6941](https://github.com/melodic-software/claude-code-plugins/issues/6941), [#6942](https://github.com/melodic-software/claude-code-plugins/issues/6942),
[#6943](https://github.com/melodic-software/claude-code-plugins/issues/6943), [#6944](https://github.com/melodic-software/claude-code-plugins/issues/6944), [#6945](https://github.com/melodic-software/claude-code-plugins/issues/6945),
[#6946](https://github.com/melodic-software/claude-code-plugins/issues/6946), [#6997](https://github.com/melodic-software/claude-code-plugins/issues/6997), and
[melodic-software/ci-runner#463](https://github.com/melodic-software/ci-runner/issues/463).

## Map

Full verified upstream↔ours map (35 skills at v1.2.3, with a v1.3 delta section for the 37 at
`d81f3a1`; relations, deltas, drift findings):
[`docs/upstream/mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md).

Shipping-course SSOT (distinct source from this skills-repo record; course pages
are account-gated; recheck trigger lives there):
[`aihero-shipping-course.md`](aihero-shipping-course.md).
That file owns the candidate index (C1–C23) and the lane verdicts. Where a candidate touches a
skills-repo artifact, its disposition is attached to the owning attribution row above — `to-spec`
C1–C4, `to-tickets` C5–C8 + C17, `tdd`/`tests.md`/`mocking.md` C9–C11, `code-review` C12–C16,
`wayfinder` C18–C20, `.agents/invocation.md` C21–C23 in the tracked strand — never re-indexed
here as a second table.

Crash-course + Steering-section provenance record (the course's original six lessons and nine
steering lessons, vetted as lanes with per-lesson coverage index and term-adoption decisions;
its own divergence-at-re-fetch trigger discipline lives there):
[`aihero-course.md`](aihero-course.md).
