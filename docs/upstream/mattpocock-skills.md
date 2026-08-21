# Upstream source — mattpocock/skills

Single source of truth for everything in this marketplace derived from
[mattpocock/skills](https://github.com/mattpocock/skills) (Matt Pocock, "AI Skills for Real
Engineers", MIT). Provenance lives HERE and in plugin CHANGELOGs — never in skill bodies, where
it is agent-facing noise. Content citations an agent actually uses (e.g. the Fowler smell
baseline in `review`) are not provenance records and stay in place.

**Last audited upstream state:** v1.2.3, `main@84fdeff` (this repo's audit: the
`pocock-skills-v12-sync` topic). Git history of this file records *when*; this line records only
*what was audited*.

**Recheck trigger:** a mattpocock/skills release whose changeset names any skill in the
attribution table below — re-audit the affected row(s). Release notes name skills explicitly
(`gh release view <tag> -R mattpocock/skills`).

## Attribution table

| Upstream skill / source | Ours | Relation | What was taken / rejected |
|---|---|---|---|
| `to-questionnaire` (Productivity; graduated from in-progress in v1.2.0 #593) | `planning:questionnaire` | Derived | Interview-the-send invariant kept; output relocated cwd → topic-docs memory slice (PII); grill→interview vocabulary; tracker-item option added. Re-audited against v1.2.3: no delta — his graduation commit is a 100%-similarity rename, his one body change (template XML-ification) is already reflected in our template, and ours is otherwise a superset (route-away, overwrite guard, role-slug multi-recipient) |
| `wayfinder` | `planning:wayfind` | Partial | Fog-of-war framing + ticket-vs-fog (sharpness) distinction; REJECTED file-based map (native tracker primitives instead) and upstream tracker seam. v1.2 re-audit: ADOPTED parallel research burn-down (work-mode exception + chart-mode offer) and the in-chart no-fog bail-out; "decision ticket" term present as our "decision item" (parity under work-items vocabulary); REJECTED `research/<name>` branch (two-lane branch-naming prohibition; resolution comments + memory tier already home the findings); map-clears handoff already present-stronger (named graduation targets). Course lane W (#2939): **C18 ADOPTED** (human-facing narration names items by title, number as link or suffix; `wayfind` only, not generalized to work-items); **C19 ADOPTED** (Out-of-scope is for scope not sharpness, fog never graduates there, a wrongly scoped item is closed + one linking line); **C20 ALREADY-PRESENT** (map-as-index — a decision lives in its own item; the map gists and links, never restates) |
| `batch-grill-me` / `grilling` rounds | `planning:interview` (propagated to `prd`/`design`/`plan`) | Derived (behavior) | Frontier-rounds model, facts-vs-decisions split, confirmation gate; no-grill vocabulary constraint; background fact sub-agents. v1.2 re-audit: ADOPTED ❓/➡️ emoji anchors as opt-in `userConfig` (`use_emoji_question_markers`, default off; decoration of the single verdict marker); answer-by-number dictation and any-order answering confirmed already present; REJECTED one-question-at-a-time opt-out line (his seam is the consumer's own global CLAUDE.md — platform-native, nothing for the plugin to ship) |
| grilling-family rework (upstream PR #532) | `planning:interview`, `architecture:improve` | Partial | decision-tree rename, domain-routing, primitive-vs-variant boundary; ADR 3-gate + glossary purity previously recorded as house additions — **annotated 2026-08-18 (lane 5 audit-answers pass, two independent validators):** current upstream main's `domain-modeling` carries both near-identically; direction/timing unverifiable at annotation time (upstream git history behind a blocked API) — treat as convergent-or-derived, not house-original |
| `git-guardrails-claude-code` (misc) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Capability adopted; substring-matching implementation REJECTED wholesale (false-blocks) — house argv-grammar parser instead |
| upstream PR #464 (review checklist) | `review` code-reviewer Fowler baseline | Pointer | Surfaced the idea; content re-derived from Fowler, *Refactoring* 2nd ed. ch. 3 — no upstream phrasing |
| `code-review` (course flow skill; distinct from PR #464 above) | `review` — `quality-gate` lenses, `fanout`, code-reviewer agent | Partial | Course lane D (#2937): **C12 ADOPTED-corrected** (spec axis as a 9th `quality-gate` lens, `context/spec.md` owning the missing / scope-creep / wrong enum; branch-scoped — the container-scoped consumer was filled later by the close-out lens, not this one); **C13 ALREADY-PRESENT + one edit** (two-axis intent already implemented as `fanout`'s two-axis presentation; the proposed never-merge/never-rerank rule WITHDRAWN — it negates the normalization pipeline `fanout` exists to run; `axis` vs `lens` vocabulary recorded once in `review/context/severity.md`); **C14 ADOPTED-corrected** (spec-source discovery ladder, with bare-`#N` validation-and-promotion, provider-mechanic read, and a topic-slug rung); **C15 PARTIAL** (fail-fast preflight ported, mode-scoped with `allowed-tools` widened; `fanout`'s untracked-only stop deliberately NOT copied); **C16 ALREADY-PRESENT** (both suppression halves already in `code-reviewer.md`). Map row 2 |
| upstream issues #186/#306/#617/#482 (handoff failures) | `session-flow` handoff claim-provenance + constraint re-scan rules | Derived (failure corpus) | Two rules adopted from incident threads; rest rejected (verdicts on issue #1477) |
| `triage` + its `.out-of-scope/` KB (`OUT-OF-SCOPE.md`) | `work-items:triage` | Derived (structured port) | "A PR is an item with attached code" ≈ upstream's "a PR is an issue with attached code"; state-machine framing convergent. Corrected in lane 5 — this row previously claimed "no structured port", which is provably false: the rejected-concept ledger (work-items 0.6.0; triage's ledger check + won't-fix/already-implemented outcomes) is a structured port of upstream's `.out-of-scope/` KB — one-file-per-concept, concept-similarity-not-keyword matching, never-ledger-built-features, and the near-verbatim "so the same request doesn't return as fresh code" (upstream `OUT-OF-SCOPE.md:86`) map one-to-one; ours is a superset. The v1.2 `.out-of-scope/` adoption candidate (M15) is therefore REJECTED as already-adopted; provenance row corrected only — no `work-items` behavior change (the topic plan's out-of-scope bars it) |
| `to-spec` | `planning:plan` / `planning:prd` Brief + `work-items:decompose` container lifecycle | Partial | Course lane A (#2934): **C1 ALREADY-PRESENT** (no-interview pure-synthesis mode — `planning:interview` synthesizes directly when intent is clear; `plan`'s empty-argument default finalizes without re-interviewing); **C2 PARTIAL, routed to lane C** (#2936 — seam-sketch-before-spec lands beside C9; the "ideal number of seams is one" absolutism REJECTED, folklore-figure posture); **C3 PARTIAL** (optional `## Testing decisions` section with prior-art test pointers adopted; the "LONG, numbered, extremely extensive" directive stays excluded); **C4 ADOPTED (gate-added variant)** (spec publishes to the tracker as a `work-map` container with slices as native sub-items; upstream's gate-free publish excluded). Course-only "archive-your-specs" ADOPTED as archival-by-closure. Map row 14 |
| `to-tickets` | `work-items:decompose` | Partial | Vertical-slice / tracer-bullet vocabulary overlaps upstream and the seam plumbing is house-built — but "influence (vocabulary)" understated it, and disagreed with map row 15, which already graded this PARTIAL. Lane B (#2935) adopted four **mechanics**, not just phrasing: prefactor-as-blocker (C5, `decompose/SKILL.md:67`), the one-fresh-context-window sizing bar (C6, `:69`), the integration-branch fallback (C7, `:102`), and the PR-variant agent brief (C17, `agent-brief.md:82`). Only C8 — "work the frontier" (`:106`) — is vocabulary. Lane B verdicts: **C5, C6, C7, C8, C17 all ADOPTED** |
| `tdd` / `tests.md` / `mocking.md` | `planning:plan` Test strategy, `tdd:principles`, `testing:write`, `review` code-reviewer | Partial | Course lane C (#2936): **C9 PARTIAL, relocated** (pre-agreed-boundary discipline lands in `plan`'s existing Test strategy element — deliberately NOT phrased as "seam" (fleet-registered vocabulary) and NOT hosted by `implementation:phase-verifier`; upstream's hard consent gate softened to a `DEVIATIONS.md` record an unattended run can satisfy); **C10 ALREADY-PRESENT (prose)** (tautological-test anti-pattern at `anti-patterns-khorikov.md` + `testing/write`; the prose-only coverage was an overstatement corrected in-lane, and the executable half landed as a `code-reviewer.md` criterion, `review` 0.24.0, ceding the textually-identical core to `cant-fail-scan.sh`); **C11 ALREADY-PRESENT + one clause** (`test-doubles.md` has carried SDK-style-interfaces-over-generic-fetchers since `85aa8066`; added only the missing subordination clause — the shape rule never widens *what* gets mocked). Zero-assembly chain doc REJECTED with reasons (the drafted chain was factually wrong). Map row 13 |
| `improve-codebase-architecture` YAGNI scoping filter (v1.2 #533) | `architecture:improve` deepening Phase 1 | Partial | ADOPTED scope-before-scanning: user-named direction scopes the scan, else recent-commit hot spots pull attention first (precomputed context widened to 20 commits). REJECTED his `CONTEXT.md` reference (our glossary-discovery ladder) and HTML-report machinery (previously rejected) |
| `diagnosing-bugs` (v1.2.3 Redact + tagged logs) | `debugging:debug`, `testing:diagnose` | Partial | ADOPTED the redaction guard in both skills (secrets `<REDACTED>` before any shown command/output/artifact; env-var credentials; signal-lines-only quoting) and the `[DEBUG-a4f2]` tagged-log convention in `testing:diagnose` (already present in `debugging:debug`). TRACKED, not adopted: feedback-loop-first doctrine (10 ranked loop types, 3–5 ranked hypotheses) — our phase structures work; re-evaluate on a release whose changeset names `diagnosing-bugs`. Annotation (lane 6, 2026-08-18, from the 2026-08-17 pre-lane recheck at unreleased main `068b6e0`): upstream dropped its Phase 6 post-mortem step ("Cleanup + post-mortem" → "Cleanup"; the what-would-have-prevented-this handoff removed) — when the release trigger fires, the re-evaluation grades the post-drop shape |
| `wait-what` (Productivity, NEW in v1.2 #751) | `discipline:wait-what` | Derived | Ported near-verbatim (one-sentence re-pitch body: back up, add missing context, ASD-STE100 register + inline gloss, ubiquitous language) as a declared non-corrector species in `discipline` beside `tighten-your-output`/`mind-your-maxims` — home chosen on the blame axis (the drift is the model's output, not the user's comprehension). Name KEPT with an explicit PLUGIN-PHILOSOPHY naming-exception entry (utterance-is-mechanism + upstream muscle-memory parity; a 5-generator/3-judge naming tournament's grammar-clean winner `re-pitch` was declined by the user). REJECTED his fixed `CONTEXT.md` filename (our format-externalized glossary discovery: nearest glossary per consumer convention, silent degradation). Shape evidence: his X thread (status 2084753070437609606 → 2084941367659168064 → 2085681281795232026) — the same instruction failed as passive global CLAUDE.md AND as an output style; only the on-demand skill works, so the register text lives in the body, invoked at the moment of loss |
| `wizard` (Engineering; graduated from in-progress in v1.2) | `wizard:generate` | Derived | PORTED (lane 4) as a new single-capability plugin `wizard` 0.1.0, hardened. Kept: the 4-step scope/map/author/verify process, the fixed never-hand-edited library above the `STAGES` marker, model-invoked posture with the explicit non-trigger fence, gh-absence graceful degradation, ephemeral-by-default doctrine, agent-authors-never-runs doctrine. Hardened beyond upstream (deltas enumerated in `plugins/wizard/CHANGELOG.md` 0.1.0): mandatory human read-and-approve of the full STAGES block before `chmod +x`; https-only `open_url` (also closes a Windows UNC/NTLM leak via explorer.exe); `/dev/tty` fail-closed prompts (retires a verified multi-line-paste confirm bypass and `pause`'s fail-open at EOF); quoted `0600` `.env` writes + gitignore assert + trap-cleaned atomic temp; repo-resolved/confirmed `--repo`-explicit gh writes with stderr surfaced and empty values refused; key-name validation; readline on non-secret asks (fixes upstream #741 where safe); names-only live-`.env` scoping with the secrets-and-context property stated honestly. REJECTED: Codex `agents/openai.yaml` sidecar (no Codex target — standing precedent) |
| `prototype` `LOGIC.md` shareable-HTML demo (Engineering, v1.2) | `prototype:pressure-test` | Partial | ADOPTED (lane 5) the audience-routed HTML demo shell: TUI stays default; when the driver is a non-developer (designer, PM, domain expert) or no terminal fits, the disposable shell over the same portable pure logic module is one self-contained `file://` page — domain-language labels, labelled state panel re-rendered per click, free-play buttons, guided-walkthrough scenarios resetting to a known initial state — under explore-directions' existing HTML-substrate constraint set reused verbatim-in-spirit (restrictive CSP meta tag, ephemeral `mktemp -d` / `%LOCALAPPDATA%\Temp` placement, synthetic data only, discard after the markdown capture). prototype 0.5.0. REJECTED the other half of upstream's step 5: the throwaway-branch "primary source" capture that keeps the prototype re-runnable on a branch — a two-lane branch-naming posture violation that also contradicts the plugin's delete-when-done discipline (`plugins/prototype/context/discipline.md`, "Delete or absorb when done") |
| ask-matt `PHASE-BOUNDARIES.md` (v1.2) | `session-flow:workflow` continuation router + `context-guard` zones | Convergent / rejected | Tree audited element-by-element at parity or stronger (ordered first-yes-wins router, compact-last-with-steering, boundary-only trigger; ours adds clean-stop, user-gated background, instrumented zones, worker relay). ADOPTED one zone-gated criterion: prefer continue when the next stage consumes this stage's reasoning verbatim. REJECTED "handoff only for what travels" narrowing (contradicts our fork-beats-compaction stance) and the ~150k smart-zone figure (self-declared-debated folklore; no official numeric threshold exists — our baseline is instrumented zone readings plus context-guard's declared judgment-default bands with named provenance (corrected 2026-08-18 per audit amendment A1: the bands are declared defaults, not measurements; only zone readings are measured), his dictionary entry noted as one more folklore anchor) |
| `teach` (Productivity) | `education:teach` | Derived | Corrected by the `teach-skill-comparison` topic audit (PR #2958) — this row previously sat under "Not adopted", which is provably false: the original port took his workspace vocabulary (MISSION / GLOSSARY / RESOURCES / NOTES + learning records as "teaching ADRs"), near-verbatim FORMAT-spec content, and the K-S-W / ZPD / community-delegation pedagogy with learning-record doctrine. REJECTED: cwd-as-workspace (dedicated per-project workspace roots instead), Codex `agents/openai.yaml` sidecar (standing precedent), HTML references (the durable trio — reference, records, glossary — stays markdown). ADDED house-built: codebase mode, primer action, assess, staleness doctrine, evals, slug-collision guards, workspace-root resolution ladder. RE-ADOPTED in the same audit (education 0.7.0): storage-strength pedagogy (fluency-vs-storage, desirable-difficulty triad, knowledge/skills asymmetry, equal-length quiz answers) and HTML-first interactive lessons with a shared `assets/` library (answer-shuffling quiz component — fixes his #335 class of always-option-C bug); his acknowledged no-review-scheduling gap is out-executed via spaced review surfaced at resume/status from learning-record age × domain velocity |

## Not adopted (decided, with reasons)

`ask-matt` router (marketplace shape differs), `setup-matt-pocock-skills` (we configure via
`userConfig` + consumer docs), `migrate-to-shoehorn` /
`scaffold-exercises` / `setup-pre-commit` (personal/low-value), writing-beats/-fragments/-shape
(out of scope), Codex `agents/openai.yaml` sidecars (no Codex target). (`teach` moved to the
attribution table — the `teach-skill-comparison` topic audit established it as Derived.)

Lane-5 infra rejections (v1.2):

- **Version-sync script** (his `scripts/` changeset-version sync): serves upstream's
  changesets/npm release pipeline, which this marketplace does not have; our CI-wired
  `scripts/check-changelog-parity.sh` (`.github/workflows/ci.yml` changelog-parity job) is the
  stronger gate; the version one-home doctrine holds — `marketplace.json` carries no version
  keys to drift.
- **"It's working if" sections** (per-skill success blurbs): they decorate a per-skill docs site
  this marketplace doesn't build (docs-site build is out of scope per the topic plan). Reopen
  condition: a docs-site build landing in this repo — recorded here, deliberately not a TRACK
  row.
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
PRs 878/880) is recorded in the pocock-course-lanes pre-lane recheck. Verdict per upstream
section — where each concern lives here, or the recorded gap. The structural finding behind
the supersession: upstream fires at the *authoring* moment ("creating or editing skills, or
modifying AGENTS.md or CLAUDE.md") while our coverage is *audit*-shaped; only skills have an
authoring-moment home (`playbooks:skill-authoring`).

**Lane 7 closed 2026-08-17**: gaps 1–2 and the two-loads/leading-words strands are
design-locked as `docs-hygiene:write-for-agents`
(contract: `docs/specs/write-for-agents-brief.md`; build:
[#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962) +
[#2963](https://github.com/melodic-software/claude-code-plugins/issues/2963), the audit-side
completion-criteria criterion). **#2962 built (docs-hygiene 0.17.0)**: the gap-1/2 verdict
cells below are ADOPTED; #2963's audit-side criterion remains the one open follow-on.

**Lane 8 closed 2026-08-17**: gap 3 (invocation) is decided — invocation-mode rubric homed at
`docs/conventions/invocation-mode/README.md` (model-invoked default + three exception classes;
contract: `docs/specs/invocation-mode-doctrine-brief.md`); enforcement filed as
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
| Pruning: single source of truth | `docs-hygiene:extract-ssot` + the topic-docs single-home rule | PARITY+ |
| Pruning: environment-as-truth ("cache") | `docs-hygiene:audit-derivability` (keep-as-derivation-cache verdict + drift control) | PARITY+ (stronger — cache without drift control is not a cache) |
| Pruning: relevance / sediment | `claude-config:audit-instructions`, `session-flow:reanchor`, `docs-hygiene:rename-references`, `review` doc-drift-detector | PARITY |
| Pruning: no-ops (model-relative, run-the-document test) | `claude-config:unhobble` (empirical — operationalizes his remove-and-observe test) + `audit-instructions` (judgment) | PARITY+ |
| MECHANICS: invocation choice | rubric at `docs/conventions/invocation-mode/` (model-invoked default + exception classes; the setup convention was already documented in PLUGIN-PHILOSOPHY, contra this row's earlier "undocumented" reading); `skill-quality:check listing-budget` instrument | ADOPTED (adapted — inverted default; lane 8, 2026-08-17; enforcement → #2968) |
| MECHANICS: splitting by invocation | rubric § Splitting by invocation; #2962's when-to-split doctrine points there | ADOPTED (routed; lane 8, 2026-08-17) |
| MECHANICS: router skills | rubric § Router-skill verdict; human-side answer = `docs/SKILL-CHEAT-SHEET.md` + `claude-ops:inventory`; composition-router carve-out (`discipline:sweep-all`) | REJECTED with reason (lane 8, 2026-08-17 — the always-present listing is the router under a model-invoked default) |
| Invocation-reach invariant | tracked strand (below) | CONFIRMED (docs-verified 2026-08-17; lane 8 disposition below) |

## Tracked (event-triggered re-evaluation)

Two `writing-for-agents` strands from v1.2 (lane 5) — tracked on events, never dates. Since
2026-08-17 each also has a disposition path through the steering course lanes; the event
triggers stand until the owning lane records the disposition:

- **Leading-words + negation doctrine** (upstream `writing-for-agents/SKILL.md:61-74`:
  pretrained "leading words" as compact behavior anchors; prompt the positive — prohibition
  drags the banned behavior into context). Not double-tracked: this is the same territory as
  the deliberate deferral already recorded at
  `docs/topics/interview-batch-rounds/PLAN.md:43-44` (slice carried by PR #1400; the skill-quality
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
  `claude-ops` `inventory` / `audit-performance` / `audit-install-state` (agent-operative
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
  the policy line belongs only on user-invoked skills. Relevant only if we ever target Codex.

## Map

Full verified 35-skill upstream↔ours map (relations, v1.2 deltas, drift findings):
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
