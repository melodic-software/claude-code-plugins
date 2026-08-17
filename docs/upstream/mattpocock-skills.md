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
| `wayfinder` | `planning:wayfind` | Partial | Fog-of-war framing + ticket-vs-fog (sharpness) distinction; REJECTED file-based map (native tracker primitives instead) and upstream tracker seam. v1.2 re-audit: ADOPTED parallel research burn-down (work-mode exception + chart-mode offer) and the in-chart no-fog bail-out; "decision ticket" term present as our "decision item" (parity under work-items vocabulary); REJECTED `research/<name>` branch (two-lane branch-naming prohibition; resolution comments + memory tier already home the findings); map-clears handoff already present-stronger (named graduation targets) |
| `batch-grill-me` / `grilling` rounds | `planning:interview` (propagated to `prd`/`design`/`plan`) | Derived (behavior) | Frontier-rounds model, facts-vs-decisions split, confirmation gate; no-grill vocabulary constraint; background fact sub-agents. v1.2 re-audit: ADOPTED ❓/➡️ emoji anchors as opt-in `userConfig` (`use_emoji_question_markers`, default off; decoration of the single verdict marker); answer-by-number dictation and any-order answering confirmed already present; REJECTED one-question-at-a-time opt-out line (his seam is the consumer's own global CLAUDE.md — platform-native, nothing for the plugin to ship) |
| grilling-family rework (upstream PR #532) | `planning:interview`, `architecture:improve` | Partial | decision-tree rename, domain-routing, primitive-vs-variant boundary; ADR 3-gate + glossary purity are house additions |
| `git-guardrails-claude-code` (misc) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Capability adopted; substring-matching implementation REJECTED wholesale (false-blocks) — house argv-grammar parser instead |
| upstream PR #464 (review checklist) | `review` code-reviewer Fowler baseline | Pointer | Surfaced the idea; content re-derived from Fowler, *Refactoring* 2nd ed. ch. 3 — no upstream phrasing |
| upstream issues #186/#306/#617/#482 (handoff failures) | `session-flow` handoff claim-provenance + constraint re-scan rules | Derived (failure corpus) | Two rules adopted from incident threads; rest rejected (verdicts on issue #1477) |
| `triage` + its `.out-of-scope/` KB (`OUT-OF-SCOPE.md`) | `work-items:triage` | Derived (structured port) | "A PR is an item with attached code" ≈ upstream's "a PR is an issue with attached code"; state-machine framing convergent. Corrected in lane 5 — this row previously claimed "no structured port", which is provably false: the rejected-concept ledger (work-items 0.6.0; triage's ledger check + won't-fix/already-implemented outcomes) is a structured port of upstream's `.out-of-scope/` KB — one-file-per-concept, concept-similarity-not-keyword matching, never-ledger-built-features, and the near-verbatim "so the same request doesn't return as fresh code" (upstream `OUT-OF-SCOPE.md:86`) map one-to-one; ours is a superset. The v1.2 `.out-of-scope/` adoption candidate (M15) is therefore REJECTED as already-adopted; provenance row corrected only — no `work-items` behavior change (the topic plan's out-of-scope bars it) |
| `to-tickets` | `work-items:decompose` | Influence (vocabulary) | Vertical-slice / tracer-bullet decomposition vocabulary overlaps upstream; mechanics are house-built on the work-item seam |
| `improve-codebase-architecture` YAGNI scoping filter (v1.2 #533) | `architecture:improve` deepening Phase 1 | Partial | ADOPTED scope-before-scanning: user-named direction scopes the scan, else recent-commit hot spots pull attention first (precomputed context widened to 20 commits). REJECTED his `CONTEXT.md` reference (our glossary-discovery ladder) and HTML-report machinery (previously rejected) |
| `diagnosing-bugs` (v1.2.3 Redact + tagged logs) | `debugging:debug`, `testing:diagnose` | Partial | ADOPTED the redaction guard in both skills (secrets `<REDACTED>` before any shown command/output/artifact; env-var credentials; signal-lines-only quoting) and the `[DEBUG-a4f2]` tagged-log convention in `testing:diagnose` (already present in `debugging:debug`). TRACKED, not adopted: feedback-loop-first doctrine (10 ranked loop types, 3–5 ranked hypotheses) — our phase structures work; re-evaluate on a release whose changeset names `diagnosing-bugs` |
| `wait-what` (Productivity, NEW in v1.2 #751) | `discipline:wait-what` | Derived | Ported near-verbatim (one-sentence re-pitch body: back up, add missing context, ASD-STE100 register + inline gloss, ubiquitous language) as a declared non-corrector species in `discipline` beside `tighten-your-output`/`mind-your-maxims` — home chosen on the blame axis (the drift is the model's output, not the user's comprehension). Name KEPT with an explicit PLUGIN-PHILOSOPHY naming-exception entry (utterance-is-mechanism + upstream muscle-memory parity; a 5-generator/3-judge naming tournament's grammar-clean winner `re-pitch` was declined by the user). REJECTED his fixed `CONTEXT.md` filename (our format-externalized glossary discovery: nearest glossary per consumer convention, silent degradation). Shape evidence: his X thread (status 2084753070437609606 → 2084941367659168064 → 2085681281795232026) — the same instruction failed as passive global CLAUDE.md AND as an output style; only the on-demand skill works, so the register text lives in the body, invoked at the moment of loss |
| `wizard` (Engineering; graduated from in-progress in v1.2) | `wizard:generate` | Derived | PORTED (lane 4) as a new single-capability plugin `wizard` 0.1.0, hardened. Kept: the 4-step scope/map/author/verify process, the fixed never-hand-edited library above the `STAGES` marker, model-invoked posture with the explicit non-trigger fence, gh-absence graceful degradation, ephemeral-by-default doctrine, agent-authors-never-runs doctrine. Hardened beyond upstream (deltas enumerated in `plugins/wizard/CHANGELOG.md` 0.1.0): mandatory human read-and-approve of the full STAGES block before `chmod +x`; https-only `open_url` (also closes a Windows UNC/NTLM leak via explorer.exe); `/dev/tty` fail-closed prompts (retires a verified multi-line-paste confirm bypass and `pause`'s fail-open at EOF); quoted `0600` `.env` writes + gitignore assert + trap-cleaned atomic temp; repo-resolved/confirmed `--repo`-explicit gh writes with stderr surfaced and empty values refused; key-name validation; readline on non-secret asks (fixes upstream #741 where safe); names-only live-`.env` scoping with the secrets-and-context property stated honestly. REJECTED: Codex `agents/openai.yaml` sidecar (no Codex target — standing precedent) |
| `prototype` `LOGIC.md` shareable-HTML demo (Engineering, v1.2) | `prototype:pressure-test` | Partial | ADOPTED (lane 5) the audience-routed HTML demo shell: TUI stays default; when the driver is a non-developer (designer, PM, domain expert) or no terminal fits, the disposable shell over the same portable pure logic module is one self-contained `file://` page — domain-language labels, labelled state panel re-rendered per click, free-play buttons, guided-walkthrough scenarios resetting to a known initial state — under explore-directions' existing HTML-substrate constraint set reused verbatim-in-spirit (restrictive CSP meta tag, ephemeral `mktemp -d` / `%LOCALAPPDATA%\Temp` placement, synthetic data only, discard after the markdown capture). prototype 0.5.0. REJECTED the other half of upstream's step 5: the throwaway-branch "primary source" capture that keeps the prototype re-runnable on a branch — a two-lane branch-naming posture violation that also contradicts the plugin's delete-when-done discipline (`plugins/prototype/context/discipline.md`, "Delete or absorb when done") |
| ask-matt `PHASE-BOUNDARIES.md` (v1.2) | `session-flow:workflow` continuation router + `context-guard` zones | Convergent / rejected | Tree audited element-by-element at parity or stronger (ordered first-yes-wins router, compact-last-with-steering, boundary-only trigger; ours adds clean-stop, user-gated background, instrumented zones, worker relay). ADOPTED one zone-gated criterion: prefer continue when the next stage consumes this stage's reasoning verbatim. REJECTED "handoff only for what travels" narrowing (contradicts our fork-beats-compaction stance) and the ~150k smart-zone figure (self-declared-debated folklore; no official numeric threshold exists — our measured bands stand, his dictionary entry noted as one more folklore anchor) |
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
- **`writing-for-agents` / `SKILL-MECHANICS.md` bulk**: rejected at parity or stronger — the
  derivation-cache rubric, listing-budget check, and hub-and-spoke splitting are already covered
  by our docs-hygiene and skill-quality machinery. Two strands are tracked, not rejected — see
  the tracked section below.

The v1.2 behavior deltas (owned-skill lane), the `wait-what` port, the `wizard` port, and the
infra subset (lane 5: shareable-HTML logic shell adopted — prototype row above; version-sync
script and "It's working if" rejected above; `.out-of-scope/` KB rejected as already-adopted —
triage row above; two writing-for-agents strands tracked below) are all closed — no evaluations
from the v1.2 audit remain open.

## Tracked (event-triggered re-evaluation)

Two `writing-for-agents` strands from v1.2 (lane 5) — tracked on events, never dates:

- **Leading-words + negation doctrine** (upstream `writing-for-agents/SKILL.md:61-74`:
  pretrained "leading words" as compact behavior anchors; prompt the positive — prohibition
  drags the banned behavior into context). Not double-tracked: this is the same territory as
  the deliberate deferral already recorded at
  `docs/topics/interview-batch-rounds/PLAN.md:43-44` (slice carried by PR #1400; the skill-quality
  negation/negative-space port deferred from that session's gap scan) — this record
  cross-links that deferral rather than opening a second ledger entry. Trigger: a
  mattpocock/skills release whose changeset names `writing-for-agents`.
- **Invocation-reach invariant** (upstream `SKILL-MECHANICS.md:10`: a user-invoked skill —
  `disable-model-invocation: true` — can be invoked by no other skill). **Fired-and-resolved
  (#2940 / Lane X C22):** fleet audit enumerated **57** skills with
  `disable-model-invocation: true` and searched `SKILL.md`, evals, and reference docs for
  Skill-tool invocation of those names (`invoke \`/plugin:skill\` via the Skill tool`,
  `Call the Skill tool` + target, `Skill tool` + `:setup`). **Zero** Skill-tool invocations of
  user-invoked-only targets. Human-relay phrasing ("tell the user to run /X", "offering to run
  `/…:setup`") and Skill-tool hits on model-invocable skills (`/toolchain:check`,
  `/implementation:implement-dispatch`, `/tdd:principles`, `/session-flow:handoff`,
  `/testing:run-e2e`) are non-violations. Standing `skill-quality:check` automation deferred
  (cross-plugin target resolution is not cheap under the single skills-root model); doctrine
  lines live in `playbooks:skill-authoring` and `skill-quality:check`. Canonical rewording if a
  future hit appears: "tell the user to run /X". Same Lane X pass: C23 curate-language
  trigger comparison vs upstream artifact-anchored `domain-modeling` rewording is
  **ALREADY-PRESENT** (ours already name glossary / domain term / vocabulary) — one-shot, not
  a re-evaluation trigger. Re-trigger: a mattpocock/skills release whose changeset names
  `writing-for-agents`, OR a repo review/audit surfacing a new Skill-tool invocation of a
  `disable-model-invocation: true` target.

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
